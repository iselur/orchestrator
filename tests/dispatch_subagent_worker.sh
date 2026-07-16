#!/usr/bin/env bash
# R73 Job 3: subagent worker mode (owner simplification 2026-07-16). Claude-vendor workers BUILD
# inside the orchestrator session; `dispatch continue` runs the ONE shared grading half. This
# proves: the registry/mode surface; mode freezing at resolution; the external-CLI pipeline
# refusing subagent records and _grade refusing external-CLI records (both TERMINAL); continue's
# fail-closed preconditions and its atomic awaiting_build->running claim; the deadline expiry
# paths (continue and reconcile); await/health treating awaiting_build as pending-by-design; and
# the codex worker prompt surviving the worker_prompt_text factoring byte-identically.
# Same box-only skip contract as tests/dispatch_fail_closed.sh (venv-needing self-test).
set -uo pipefail
cd "$(dirname "$0")/.."

PY="${ORCH_TEST_PY:-.venv/bin/python}"
if [ ! -x "$PY" ] || ! "$PY" -c 'import yaml, jsonschema' 2>/dev/null; then
  echo "SKIP dispatch_subagent_worker.sh: .venv/pyyaml/jsonschema absent (dispatcher self-test runs on the box only, not CI)"
  exit 77   # did NOT run — never a pass (T1/R26)
fi

"$PY" - <<'PY'
import contextlib, hashlib, importlib.util, io, json, pathlib, sys, tempfile, time

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

d = load("d", "scripts/dispatch.py")
va = load("va", "scripts/vendor_adapters.py")

fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails.append(name)

# ---- adapter surface -----------------------------------------------------------------------
w = va.get_worker_adapter("claude")
check("claude worker adapter mode is subagent", va.worker_mode("claude") == "subagent")
raw = pathlib.Path(tempfile.mkdtemp())
check("last message absent reads empty (continue refuses upstream)",
      w.recover_last_message(raw, True) == "")
(raw / "worker-last-message.txt").write_text("done, all tests green")
check("last message reads the orchestrator-written file (both isolation flags)",
      w.recover_last_message(raw, True) == "done, all tests green"
      and w.recover_last_message(raw, False) == "done, all tests green")
check("classify_error is always completion — no CLI vocabulary to speak",
      w.classify_error(None, "", raw) is None and w.classify_error(1, "boom", raw) is None)
try:
    va.worker_mode("gemini")
    check("worker_mode unknown vendor raises (fail closed)", False)
except ValueError:
    check("worker_mode unknown vendor raises (fail closed)", True)

# ---- mode freezes at resolution -------------------------------------------------------------
CFG = {"schema_version": "1",
       "roles": {"orchestrator": {"model": "claude-opus-4-8", "effort": "high"},
                 "spec_author": {"model": "gpt-5.6-sol", "effort": "high"},
                 "utility_subagent": {"model": "claude-sonnet-4-6", "effort": "default"},
                 "worker": {"model": "claude-sonnet-4-6", "effort": "high"},
                 "bound_reviewer": {"model": "claude-fable-5", "effort": "high"},
                 "orchestrator_artifact_reviewer": {"model": "gpt-5.6-sol", "effort": "high"}},
       "reviewer_failover": {"trigger_model": "claude-fable-5",
                             "fallback_model": "claude-opus-4-8"},
       "cli_aliases": {"claude-fable-5": "fable"},
       "vendor_map": {"gpt-5.6-luna": "codex", "gpt-5.6-sol": "codex",
                      "claude-fable-5": "claude", "claude-opus-4-8": "claude",
                      "claude-sonnet-4-6": "claude"}}
r = d.resolve_launch_models({}, CFG)
check("claude worker freezes worker_mode=subagent at resolution",
      r["worker_vendor"] == "claude" and r["worker_mode"] == "subagent")
cfg2 = json.loads(json.dumps(CFG)); cfg2["roles"]["worker"]["model"] = "gpt-5.6-luna"
r2 = d.resolve_launch_models({}, cfg2)
check("codex worker freezes worker_mode=external-cli at resolution",
      r2["worker_vendor"] == "codex" and r2["worker_mode"] == "external-cli")
cfg3 = json.loads(json.dumps(CFG)); cfg3["roles"]["worker"]["model"] = "claude-fable-5"
try:
    d.resolve_launch_models({}, cfg3)
    check("claude worker == reviewer model still refuses (self-review)", False)
except SystemExit:
    check("claude worker == reviewer model still refuses (self-review)", True)

# ---- awaiting_build is LIVE ------------------------------------------------------------------
check("awaiting_build counts as a LIVE status (claim_slot concurrency, reconcile)",
      "awaiting_build" in d.LIVE and "awaiting_build" not in d.TERMINAL)

# ---- external-CLI pipeline refuses a subagent record (TERMINAL) ------------------------------
snap = b"id: SPEC-000\n"
att = pathlib.Path(tempfile.mkdtemp()); (att / "raw").mkdir()
(att / "spec-snapshot.yaml").write_bytes(snap)
digest = hashlib.sha256(snap).hexdigest()
lc_sub = {"spec_digest": digest, "isolation": True, "deadline_ts": time.time() + 3600,
          "worker_vendor": "claude", "reviewer_vendor": "codex", "worker_mode": "subagent"}
recorded = {}
class _Stop(Exception): pass
def _finish(status, error_class, **kw):
    recorded["status"], recorded["error_class"] = status, error_class
    recorded["detail"] = kw.get("detail", "")
    raise _Stop()
try:
    d._run_pipeline("SPEC-000-1", "SPEC-000", 1, att, lc_sub,
                    pathlib.Path("/nonexistent-wt"), att / "raw", _finish)
except _Stop:
    pass
check("external-CLI pipeline refuses a frozen subagent record as error_launch (TERMINAL)",
      recorded.get("status") == "error_launch" and recorded["status"] in d.TERMINAL
      and "continue" in recorded.get("detail", ""))

# ---- _grade / cmd_continue against patched state roots ---------------------------------------
work = pathlib.Path(tempfile.mkdtemp())
d.ATTEMPTS, d.STATE = work / "attempts", work / "state"
AID, SID, N = "SPEC-900-1", "SPEC-900", 1
attd = d.ATTEMPTS / SID / "1"; (attd / "raw").mkdir(parents=True)
(attd / "spec-snapshot.yaml").write_bytes(snap)

def write_lc(**over):
    lc = {"attempt_id": AID, "spec_id": SID, "attempt": N,
          "spec_digest": digest, "spec_snapshot_digest": digest,
          "base_sha": "0" * 40, "branch": f"codex/{AID}", "base_branch": "ready-for-main",
          "worktree": str(work / "wt"), "worker_model": "claude-sonnet-4-6",
          "worker_effort": "high", "reviewer_model": "claude-fable-5",
          "reviewer_effort": "high", "reviewer_failover_trigger": "claude-fable-5",
          "reviewer_fallback_model": "claude-opus-4-8", "cli_aliases": {},
          "worker_vendor": "claude", "reviewer_vendor": "claude", "worker_mode": "subagent",
          "test_command": "true", "approved_scope": ["**"],
          "hard_ceiling_hours": 1.0, "deadline_ts": time.time() + 3600,
          "remediation": None, "isolation": True, "exposure_accepted": False,
          "worker_unit": f"codex-worker-{AID}", "test_unit": f"codex-test-{AID}"}
    lc.update(over)
    (attd / "launch.json").write_text(json.dumps(lc))
    return lc

def state_now():
    return json.loads((d.STATE / f"{SID}.json").read_text())

def run_die(fn, *a):
    """Call a dispatcher command, capturing die()'s SystemExit code."""
    try:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            fn(*a)
        return 0, out.getvalue()
    except SystemExit as e:
        return e.code, ""

# continue: refuses an external-CLI record
write_lc(worker_mode="external-cli", worker_vendor="codex")
rc, _ = run_die(d.cmd_continue, AID)
check("continue refuses an external-CLI attempt (exit 6)", rc == 6)

# continue: refuses a missing last message
write_lc()
rc, _ = run_die(d.cmd_continue, AID)
check("continue refuses when raw/worker-last-message.txt is absent (exit 6)", rc == 6)

# continue: refuses when state is not awaiting_build
(attd / "raw" / "worker-last-message.txt").write_text("built")
d.write_state(SID, {"attempt_id": AID, "spec_id": SID, "attempt": N,
                    "spec_digest": digest, "status": "running"})
rc, _ = run_die(d.cmd_continue, AID)
check("continue refuses unless the attempt awaits its BUILD (exit 8)", rc == 8)

# continue: exhausted deadline is a durable terminal interrupt, no unit started
write_lc(deadline_ts=time.time() - 5)
d.write_state(SID, {"attempt_id": AID, "spec_id": SID, "attempt": N,
                    "spec_digest": digest, "status": "awaiting_build"})
rc, _ = run_die(d.cmd_continue, AID)
check("continue on an exhausted deadline exits 10 and records interrupted",
      rc == 10 and state_now()["status"] == "interrupted")

# continue: happy path claims the slot atomically and starts the grading unit
write_lc()
d.write_state(SID, {"attempt_id": AID, "spec_id": SID, "attempt": N,
                    "spec_digest": digest, "status": "awaiting_build"})
captured = {}
_orig_run = d.run
def _fake_run(cmd, **kw):
    captured["cmd"] = cmd
    class R: returncode = 0; stderr = ""
    return R()
d.run = _fake_run
try:
    rc, out = run_die(d.cmd_continue, AID)
finally:
    d.run = _orig_run
check("continue flips awaiting_build->running under the state lock and prints the attempt id",
      rc == 0 and state_now()["status"] == "running" and AID in out)
check("continue starts `dispatch _grade <attempt>` in the attempt's own unit",
      captured["cmd"][-2:] == ["_grade", AID]
      and any(a == f"--unit={d.unit_name(SID, N)}" for a in captured["cmd"]))
# a second continue must lose the claim (no double grading unit)
rc, _ = run_die(d.cmd_continue, AID)
check("a second continue is refused after the claim (exit 8)", rc == 8)

# _grade: refuses an external-CLI record with a TERMINAL result
write_lc(worker_mode="external-cli", worker_vendor="codex")
rc, _ = run_die(d._grade, AID)
res = json.loads((attd / "result.json").read_text())
check("_grade refuses an external-CLI record as error_launch (TERMINAL result on disk)",
      rc == 1 and res["status"] == "error_launch" and res["status"] in d.TERMINAL)

# _grade: honors SPEC_BLOCKED through the shared grading half
write_lc()
(attd / "raw" / "worker-last-message.txt").write_text("SPEC_BLOCKED\nimpossible criteria")
rc, _ = run_die(d._grade, AID)
res = json.loads((attd / "result.json").read_text())
check("_grade routes the subagent message through the shared half (spec_blocked recorded)",
      rc == 1 and res["status"] == "spec_blocked"
      and "orchestrator trust domain" in res["isolation"])

# await: awaiting_build is pending-by-design, never a silent poll or false interrupt
d.write_state(SID, {"attempt_id": AID, "spec_id": SID, "attempt": N,
                    "spec_digest": digest, "status": "awaiting_build"})
rc, out = run_die(d.cmd_await, AID)
check("await says awaiting_build and exits 3 (neither pass nor failure)", rc == 3)

# health: not-applicable for a pending BUILD
rc, out = run_die(d.cmd_health, AID)
check("health reports not-applicable for awaiting_build", rc == 0)

# reconcile: fresh awaiting_build is reported pending, not relabeled
_orig_units = d._list_codex_units
d._list_codex_units = lambda: ([], True)
try:
    rc, out = run_die(d.cmd_reconcile)
    rep = json.loads(out)
    row = [r for r in rep["reconciled"] if r.get("attempt_id") == AID][0]
    check("reconcile keeps a fresh awaiting_build pending (no unit by design)",
          row.get("status") == "awaiting_build" and state_now()["status"] == "awaiting_build")
    # expired: reconcile relabels to interrupted (fail closed on the frozen deadline)
    write_lc(deadline_ts=time.time() - 5)
    rc, out = run_die(d.cmd_reconcile)
    rep = json.loads(out)
    row = [r for r in rep["reconciled"] if r.get("attempt_id") == AID][0]
    check("reconcile expires awaiting_build at the frozen deadline",
          row.get("to") == "interrupted" and state_now()["status"] == "interrupted")
finally:
    d._list_codex_units = _orig_units

# ---- codex worker prompt is byte-identical through the factoring -----------------------------
lc_prompt = {"spec_digest": digest, "spec_snapshot_digest": digest,
             "remediation": {"remediation_number": 1, "limit": 2, "of_attempt": 1,
                             "findings": {"f": ["x"]}}}
expected = (
    "Implement this spec. Modify only in-scope paths. Run the test command until it exits 0. "
    "Leave your changes in the working tree; do NOT commit or push — the orchestrator commits "
    "your work.\n"
    "Inspect relevant code and tests before editing. For non-trivial tasks, maintain a "
    "concise, revisable implementation checklist covering intended files and verification; "
    "skip it for trivial tasks. The approved spec and evidence gates remain binding. If "
    "discovery invalidates the spec or approved scope (impossible acceptance criteria, wrong "
    "test command, inadequate scope), stop and report SPEC_BLOCKED on its own line followed by "
    "the reason — never improvise beyond the spec."
    + "\n\n=== SPEC ===\n" + snap.decode()
    + "\n\n=== REMEDIATION (attempt 2; remediation #1 of max 2) ===\n"
    + "A previous attempt (#1) FAILED. Your job is to address these specific findings — "
    + "nothing else. Stay strictly within the approved scope. If the findings cannot be "
    + "addressed within the spec and scope, report SPEC_BLOCKED.\n"
    + json.dumps({"f": ["x"]}, indent=2))
check("worker prompt is byte-identical to the pre-split builder (incl. remediation block)",
      d.worker_prompt_text(att, lc_prompt, 2) == expected)

sys.exit(1 if fails else 0)
PY
rc=$?
if [ $rc -ne 0 ]; then
  echo "FAIL dispatch_subagent_worker.sh"
  exit 1
fi
echo "PASS dispatch_subagent_worker.sh"
