#!/usr/bin/env bash
# Fail-closed regressions for audit mediums B9/B10/B14/B16 (fix batch M1).
#
# Exercises the REAL functions in scripts/dispatch.py against synthetic state and a real temp git
# repo — no workers launched, no reviewer called (the claude invocation is monkeypatched). Same
# box-only skip contract as tests/dispatch_gate4.sh: the CI runner has no venv; SKIP LOUDLY there.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${ORCH_TEST_PY:-.venv/bin/python}"
if [ ! -x "$PY" ] || ! "$PY" -c 'import yaml, jsonschema' 2>/dev/null; then
  echo "SKIP dispatch_fail_closed.sh: .venv/pyyaml/jsonschema absent (dispatcher self-test runs on the box only, not CI)"
  exit 77   # did NOT run — never a pass (T1/R26)
fi

"$PY" - <<'PY'
import contextlib, importlib.util, inspect, io, json, pathlib, subprocess, sys, tempfile

spec = importlib.util.spec_from_file_location("d", "scripts/dispatch.py")
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails.append(name)

tmp = pathlib.Path(tempfile.mkdtemp())
d.STATE = tmp / "state"; d.STATE.mkdir(parents=True)

def claim_dies(name, expect_die):
    try:
        d.claim_slot("SPEC-999", {"attempt_id": "SPEC-999-1", "spec_id": "SPEC-999",
                                  "status": "launching"})
        died = False
    except SystemExit as e:
        died = (e.code == 8)
    # claim_slot may have written the launching state; clean it for the next case
    for p in d.STATE.glob("SPEC-999*.json"):
        p.unlink()
    check(name, died == expect_die)

# B10: malformed canonical state file blocks the claim (exit 8)...
(d.STATE / "SPEC-001.json").write_text('{"truncated": ')
claim_dies("B10 malformed canonical state blocks claim", True)
(d.STATE / "SPEC-001.json").unlink()

# ...a JSON-valid non-object canonical value blocks it too...
(d.STATE / "SPEC-002.json").write_text('"just a string"')
claim_dies("B10 non-object canonical state blocks claim", True)
(d.STATE / "SPEC-002.json").unlink()

# ...but a malformed ADVISORY health sidecar must NOT block launches.
(d.STATE / "SPEC-003.health.json").write_text('{"truncated": ')
claim_dies("B10 malformed health sidecar does not block claim", False)
(d.STATE / "SPEC-003.health.json").unlink()

# B10: reconcile REPORTS malformed canonical state (and skips health sidecars) — including
# JSON-VALID non-object values, which previously crashed cmd_reconcile at st.get() before the
# malformed-state scan ran (owner-extension round-1).
(d.STATE / "SPEC-004.json").write_text('{"truncated": ')
(d.STATE / "SPEC-005.health.json").write_text('{"truncated": ')
(d.STATE / "SPEC-006.json").write_text('"just a string"')
(d.STATE / "SPEC-007.health.json").write_text('"just a string"')
d._list_codex_units = lambda: ([], True)
buf = io.StringIO()
crashed = False
with contextlib.redirect_stdout(buf):
    try:
        d.cmd_reconcile()
    except SystemExit:
        pass
    except Exception:
        crashed = True
check("B10 reconcile survives valid-but-non-object state values", not crashed)
out = json.loads(buf.getvalue())
mal = [m["file"] for m in out.get("malformed_state", [])]
check("B10 reconcile reports the malformed canonical file", any("SPEC-004" in f for f in mal))
check("B10 reconcile reports the non-object canonical file", any("SPEC-006" in f for f in mal))
check("B10 reconcile does not report health sidecars",
      not any("SPEC-005" in f or "SPEC-007" in f for f in mal))
for n in ("SPEC-004.json", "SPEC-005.health.json", "SPEC-006.json", "SPEC-007.health.json"):
    (d.STATE / n).unlink()

# B14: a failing git diff yields a FAILing scope result, never an empty PASS.
repo = tmp / "repo"; repo.mkdir()
subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q",
                "--allow-empty", "-m", "x"], cwd=repo, check=True)
res = d.scope_check(repo, "no-such-base", "no-such-head", ["**"])
check("B14 nonzero git diff fails scope", res["result"] == "FAIL" and "error" in res)
check("B14 failed diff reports no changed files as in-scope", res["changed"] == [])

# B16: reviewer envelope refused on nonzero exit; neutral cwd is outside the repo; hardened flags
# present. Heavy collaborators are monkeypatched so ONLY the invocation contract is under test.
d.git = lambda *a, **k: "diff --git a/x b/x"
d._verdict_schema_for_attempt = lambda att: {"type": "object"}
d.snapshot_spec_text = lambda att, digest: "id: SPEC-900"
captured = {}
def fake_run(cmd, **kw):
    captured["cmd"] = cmd; captured["cwd"] = kw.get("cwd")
    return subprocess.CompletedProcess(cmd, 1, stdout=json.dumps(
        {"result": json.dumps({"verdict": "PASS"})}), stderr="")
d.run = fake_run
att = tmp / "attempts" / "SPEC-900" / "1"; (att / "raw").mkdir(parents=True)
lc = {"worktree": str(repo), "base_sha": "b" * 40, "spec_digest": "d" * 64,
      "reviewer_model": "claude-fable-5", "reviewer_effort": "high"}
verdict, raw = d.review(att, "SPEC-900", lc, "c" * 40)
check("B16 nonzero reviewer exit yields no verdict even with valid JSON", verdict is None)
check("B16 reviewer runs from a cwd outside the repo",
      captured["cwd"] is not None and
      not pathlib.Path(captured["cwd"]).resolve().is_relative_to(d.ROOT.resolve()))
for flag in ("--safe-mode", "--strict-mcp-config", "--no-session-persistence"):
    check(f"B16 reviewer invocation carries {flag}", flag in captured["cmd"])
check("B16 reviewer invocation empties the tool surface",
      "--tools" in captured["cmd"] and
      captured["cmd"][captured["cmd"].index("--tools") + 1] == "")

# B9: the post-merge suite launch (run_integrate_suite) forces strict mode AND hands the suite
# a usable interpreter — without ORCH_TEST_PY the grader tree (no gitignored .venv) would skip
# the venv-dependent dispatcher self-tests, and strict mode turns that skip into a guaranteed
# integrate failure. Exercised through the REAL launch helper with run() captured, so the
# command, cwd, and environment under test are exactly what cmd_integrate passes.
suite = {}
def fake_suite_run(cmd, **kw):
    suite["cmd"] = cmd; suite["cwd"] = kw.get("cwd"); suite["env"] = kw.get("env")
    return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
d.run = fake_suite_run
gtree = tmp / "gtree"; (gtree / "scripts").mkdir(parents=True)
d.run_integrate_suite(gtree)
check("B9 suite launch runs the grader tree's own scripts/test in that tree",
      suite["cmd"] == [str(gtree / "scripts" / "test")] and suite["cwd"] == str(gtree))
check("B9 suite launch forces ORCH_TEST_STRICT=1", suite["env"].get("ORCH_TEST_STRICT") == "1")
check("B9 suite launch disables replace objects",
      suite["env"].get("GIT_NO_REPLACE_OBJECTS") == "1")
check("B9 suite launch hands the suite an interpreter",
      pathlib.Path(suite["env"].get("ORCH_TEST_PY", "")).is_absolute()
      and pathlib.Path(suite["env"]["ORCH_TEST_PY"]).exists())
# An inherited ORCH_TEST_PY must never leak through — the helper's own selection is the policy.
import os as _os
_os.environ["ORCH_TEST_PY"] = "/nonexistent/stale/python"
d.run_integrate_suite(gtree)
check("B9 inherited ORCH_TEST_PY does not leak into the suite",
      suite["env"].get("ORCH_TEST_PY") != "/nonexistent/stale/python")
# Fail-closed branch: no trusted runtime and no repo venv -> ORCH_TEST_PY stays unset, so the
# strict suite fails loudly rather than certifying a tree it could not test.
real_rt, real_root = d.trusted_test_runtime, d.ROOT
d.trusted_test_runtime = lambda: None
d.ROOT = tmp / "no-venv-root"
d.run_integrate_suite(gtree)
check("B9 no interpreter available leaves ORCH_TEST_PY unset (loud strict failure)",
      "ORCH_TEST_PY" not in suite["env"] and suite["env"].get("ORCH_TEST_STRICT") == "1")
d.trusted_test_runtime, d.ROOT = real_rt, real_root
del _os.environ["ORCH_TEST_PY"]

# R69: reviewer-model failover. Fires ONLY on the CLI's structured model-not-found envelope
# (is_error + api_error_status 404) AND only when the pinned primary (claude-fable-5) was asked
# for; one retry on the fallback, both envelopes + an escalation kept. Every other failure stays
# fail-closed with a single invocation — no error may buy the diff a second reviewer roll.
check("R69 helper accepts only the 404 model-not-found envelope",
      d.reviewer_model_unavailable(json.dumps({"is_error": True, "api_error_status": 404}))
      and not d.reviewer_model_unavailable(json.dumps({"is_error": True, "api_error_status": 500}))
      and not d.reviewer_model_unavailable("not json")
      and not d.reviewer_model_unavailable(""))

d.ESCALATIONS = tmp / "escalations"
notfound = json.dumps({"is_error": True, "api_error_status": 404})
lc69 = {"worktree": str(repo), "base_sha": "b" * 40, "spec_digest": "d" * 64,
        "reviewer_model": "claude-fable-5", "reviewer_effort": "high"}

calls = []
def failover_run(cmd, **kw):
    calls.append(cmd)
    if len(calls) == 1:
        return subprocess.CompletedProcess(cmd, 1, stdout=notfound, stderr="")
    return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(
        {"result": json.dumps({"verdict": "PASS"})}), stderr="")
d.run = failover_run
att69 = tmp / "attempts" / "SPEC-901" / "1"; (att69 / "raw").mkdir(parents=True)
verdict, raw = d.review(att69, "SPEC-901", lc69, "c" * 40)
check("R69 404 on the primary triggers exactly one fallback invocation", len(calls) == 2)
check("R69 first invocation asked for the primary model",
      calls[0][calls[0].index("--model") + 1] == "fable")
check("R69 fallback invocation asked for the fallback model",
      calls[1][calls[1].index("--model") + 1] == d.REVIEWER_FALLBACK_MODEL)
check("R69 fallback envelope is the one adopted and recorded",
      (att69 / "raw" / "review-envelope.json").read_text() != notfound
      and (att69 / "raw" / "review-envelope-primary.json").read_text() == notfound)
check("R69 failover record and escalation are durable",
      (att69 / "raw" / "reviewer-failover.json").exists()
      and any(d.ESCALATIONS.iterdir()))

calls = []
def error_run(cmd, **kw):
    calls.append(cmd)
    return subprocess.CompletedProcess(cmd, 1, stdout=json.dumps(
        {"is_error": True, "api_error_status": 500}), stderr="")
d.run = error_run
att70 = tmp / "attempts" / "SPEC-902" / "1"; (att70 / "raw").mkdir(parents=True)
verdict, raw = d.review(att70, "SPEC-902", lc69, "c" * 40)
check("R69 non-404 reviewer error stays fail-closed with a single invocation",
      verdict is None and len(calls) == 1
      and not (att70 / "raw" / "reviewer-failover.json").exists())

calls = []
def notfound_run(cmd, **kw):
    calls.append(cmd)
    return subprocess.CompletedProcess(cmd, 1, stdout=notfound, stderr="")
d.run = notfound_run
lc71 = dict(lc69, reviewer_model=d.REVIEWER_FALLBACK_MODEL)
att71 = tmp / "attempts" / "SPEC-903" / "1"; (att71 / "raw").mkdir(parents=True)
verdict, raw = d.review(att71, "SPEC-903", lc71, "c" * 40)
check("R69 404 on a non-primary model does not retry (no failover-of-the-failover)",
      verdict is None and len(calls) == 1
      and not (att71 / "raw" / "reviewer-failover.json").exists())

sys.exit(1 if fails else 0)
PY
echo "PASS dispatch_fail_closed.sh"
