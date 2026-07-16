#!/usr/bin/env bash
# R73 Job 2: worker vendor adapter (behavior-identical refactor). The role envelope —
# isolation, runtime vetting/pinning, the single attempt deadline, path-safety, commit
# packaging — stays in dispatch.py; the adapter carries only argv, unisolated env, output
# recovery, and error classification. This proves the codex adapter reproduces the
# pre-refactor mechanics EXACTLY (argv and env by full equality, not spot checks), the error
# classes are the dispatcher's own recorded vocabulary, unknown vendors refuse, and the
# module-level worker_codex_runtime() the adapter delegates to remains importable.
# Same box-only skip contract as tests/dispatch_fail_closed.sh (venv-needing self-test).
set -uo pipefail
cd "$(dirname "$0")/.."

PY="${ORCH_TEST_PY:-.venv/bin/python}"
if [ ! -x "$PY" ] || ! "$PY" -c 'import yaml, jsonschema' 2>/dev/null; then
  echo "SKIP dispatch_worker_adapter.sh: .venv/pyyaml/jsonschema absent (dispatcher self-test runs on the box only, not CI)"
  exit 77   # did NOT run — never a pass (T1/R26)
fi

"$PY" - <<'PY'
import importlib.util, json, pathlib, sys, tempfile

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

w = va.get_worker_adapter("codex")

# ---- argv: FULL equality with the pre-refactor invocations -------------------------------
WT = "/srv/codexwork/worktrees/SPEC-000-1"
PROMPT = "do the thing"
PREFIX = ["/usr/bin/node", "/opt/codex/bin/codex.js"]
LMP = "/tmp/att/raw/worker-last-message.txt"
common = ["exec", "--cd", WT, "-m", "gpt-5.6-luna",
          "-c", "model_reasoning_effort=high", "-c", "service_tier=priority",
          "--skip-git-repo-check", "--json"]
check("isolated argv is byte-identical to the pre-adapter dispatcher",
      w.build_argv("gpt-5.6-luna", "high", WT, PROMPT, isolated=True, argv_prefix=PREFIX)
      == [*PREFIX, *common, "-s", "danger-full-access", PROMPT])
check("unisolated argv is byte-identical (bwrap sandbox on, last-message file)",
      w.build_argv("gpt-5.6-luna", "high", WT, PROMPT, isolated=False,
                   last_message_path=LMP)
      == ["codex", *common, "--sandbox", "workspace-write",
          "--output-last-message", LMP, PROMPT])
check("model id passes through untranslated (no alias surface on the worker path)",
      "-m" in common and common[common.index("-m") + 1] == "gpt-5.6-luna")

# ---- unisolated env: FULL equality with the pre-refactor scrubbed dict -------------------
home = pathlib.Path("/home/op")
check("unisolated scrubbed env is identical",
      w.worker_env(home, "op") == {
          "HOME": "/home/op", "USER": "op", "LOGNAME": "op",
          "PATH": "/home/op/.local/bin:/usr/bin:/bin",
          "CODEX_HOME": "/home/op/.codex", "TERM": "dumb", "LANG": "C.UTF-8"})
check("isolated rw extra is exactly the worker's .codex dir",
      w.iso_rw_paths(pathlib.Path("/home/codex-worker")) == ["/home/codex-worker/.codex"])

# ---- runtime delegation -------------------------------------------------------------------
sentinel = (["x"], [("a", "b")], "entry")
check("runtime() delegates to the injected module-level resolver",
      w.runtime(lambda: sentinel) is sentinel)
check("worker_codex_runtime remains a module-level callable in dispatch.py",
      callable(getattr(d, "worker_codex_runtime", None)))

# ---- output recovery -----------------------------------------------------------------------
raw = pathlib.Path(tempfile.mkdtemp())
(raw / "events.jsonl").write_text(
    json.dumps({"item": {"type": "agent_message", "text": "first"}}) + "\n"
    + "not json at all\n"
    + json.dumps({"item": {"type": "other", "text": "nope"}}) + "\n"
    + json.dumps({"item": {"type": "agent_message", "text": "LAST"}}) + "\n")
check("isolated recovery takes the LAST agent_message, skipping malformed lines",
      w.recover_last_message(raw, True) == "LAST")
check("unisolated recovery with no file is empty, not an error",
      w.recover_last_message(raw, False) == "")
(raw / "worker-last-message.txt").write_text("from file")
check("unisolated recovery reads the CLI-written file",
      w.recover_last_message(raw, False) == "from file")

# ---- error classification: dispatcher vocabulary, pre-refactor decisions ------------------
check("adapter classes ARE the dispatcher's recorded vocabulary",
      (d.ERR_QUOTA, d.ERR_AUTH, d.ERR_SANDBOX, d.ERR_WORKER)
      == ("quota_rate_limit", "auth", "sandbox_denial", "worker_nonzero"))
check("429/rate limit classifies as quota", w.classify_error(1, "HTTP 429", raw) == d.ERR_QUOTA)
check("not-logged-in classifies as auth",
      w.classify_error(1, "Error: Not Logged In", raw) == d.ERR_AUTH)
empty = pathlib.Path(tempfile.mkdtemp())   # no events.jsonl at all
check("nonzero exit + no completed turn + bwrap noise classifies as sandbox",
      w.classify_error(1, "bwrap: loopback failed", empty) == d.ERR_SANDBOX)
check("nonzero exit + no completed turn classifies as generic worker error",
      w.classify_error(1, "boom", empty) == d.ERR_WORKER)
check("zero exit classifies as completion (None)",
      w.classify_error(0, "", empty) is None)
(raw / "events.jsonl").write_text('{"type":"turn.completed"}\n')
check("completed turn + nonzero exit still classifies as completion (pre-refactor rule)",
      w.classify_error(1, "warning noise", raw) is None)

# ---- registry ------------------------------------------------------------------------------
check("worker vendor registry is codex-only until Job 3", va.worker_vendors() == ["codex"])
try:
    va.get_worker_adapter("claude")
    check("unknown worker vendor raises (fail closed upstream)", False)
except ValueError:
    check("unknown worker vendor raises (fail closed upstream)", True)

sys.exit(1 if fails else 0)
PY
rc=$?
if [ $rc -ne 0 ]; then
  echo "FAIL dispatch_worker_adapter.sh"
  exit 1
fi
echo "PASS dispatch_worker_adapter.sh"
