#!/usr/bin/env bash
# Production-path tests for the kimi ACP transport in dispatch._run_pipeline
# (PLAN-009 slice 2): exact isolated_cmd argv construction (prompt absent from argv,
# "acp" subcommand present, slice/unit/env intact), small and oversized prompt
# delivery via drive(), response correlation, and fail-closed handling (zero-exit
# incomplete session → nonzero effective status; malformed frame; JSON-RPC error).
# Alias validation at the ACP call site mirrors build_argv's distinct-alias contract.
# Pure logic — no sudo, no network, no kimi install. The ACP wire protocol is
# proven by kimi_acp_driver.sh; this file proves the call-site wiring.
# Same venv-skip contract as tests/dispatch_worker_adapter.sh.
set -uo pipefail
cd "$(dirname "$0")/.."

PY="${ORCH_TEST_PY:-.venv/bin/python}"
if [ ! -x "$PY" ] || ! "$PY" -c 'import yaml, jsonschema' 2>/dev/null; then
  echo "SKIP kimi_acp_transport.sh: .venv/pyyaml/jsonschema absent (dispatcher self-test needs the dispatcher venv; CI installs it)"
  exit 77
fi

"$PY" - <<'PY'
import hashlib, importlib.util, json, pathlib, sys, tempfile, types

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

d = load("d", "scripts/dispatch.py")

fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails.append(name)

# ---- shared fixtures ----------------------------------------------------------
snap = b"id: SPEC-000\n"
att = pathlib.Path(tempfile.mkdtemp())
(att / "raw").mkdir()
(att / "spec-snapshot.yaml").write_bytes(snap)
DIGEST = hashlib.sha256(snap).hexdigest()
ALIAS = "kimi-code/k3"
WTE = pathlib.Path("/nonexistent-wt")   # worktree path for tests that stop before fs ops
# Fake runtime returned by the stubbed worker_kimi_runtime
FAKE_PREFIX = ["/opt/kimi/kimi"]
FAKE_BINDS = [("/real/kimi", "/opt/kimi/kimi")]

lc_base = {
    "spec_digest": DIGEST,
    "isolation": True,
    "deadline_ts": 4102444800.0,
    "worker_vendor": "kimi",
    "reviewer_vendor": "claude",
    "worker_model": "kimi-k3",
    "worker_effort": "max",
    "worker_unit": "kimi-SPEC-000-1",
    "cli_aliases": {"kimi-k3": ALIAS},
}

class _Stop(Exception): pass
_rec = {}
def _finish(status, error_class, **kw):
    _rec.update({"status": status, "error_class": error_class, **kw})
    raise _Stop()

class _FakeProc:
    """Minimal proc stub — fields only; drive() is stubbed away before using them."""
    stdin = None; stdout = None; returncode = 0
    def wait(self, timeout=None): return 0
    def poll(self): return 0
    def kill(self): pass

# ---- run helper ---------------------------------------------------------------
def run_pipe(lc_extra=None, prompt_text=None, drive_res=None, grade_stub=None):
    """Drive _run_pipeline for a kimi isolated attempt; return (rec, cmd_cap, drv_cap).
    Stubs out worker_prompt_text (when prompt_text given), worker_kimi_runtime,
    isolated_cmd, subprocess.Popen, and kimi_acp so no actual process is launched.
    grade_stub replaces _grade_phase when given."""
    lc = {**lc_base, **(lc_extra or {})}
    cmd_cap = {}; drv_cap = {}
    _orig_krt   = d.worker_kimi_runtime
    _orig_icmd  = d.isolated_cmd
    _orig_Popen = d.subprocess.Popen
    _orig_acp   = d.kimi_acp
    _orig_grade = d._grade_phase
    _orig_wpt   = d.worker_prompt_text

    def _fake_krt():
        return (FAKE_PREFIX, FAKE_BINDS, "/real/kimi")

    def _fake_icmd(unit, argv, cwd, rw_paths, private_network, ceiling_s,
                   binds=None, env_extra=None, slice_name=None):
        cmd_cap.update({"unit": unit, "argv": list(argv), "cwd": cwd,
                        "rw_paths": list(rw_paths), "slice_name": slice_name,
                        "env_extra": env_extra, "binds": binds})
        return ["echo", "fake"]

    def _fake_Popen(cmd, **kw):
        return _FakeProc()

    # Default drive result: effective_status=1 so _grade_phase fails closed without
    # requiring a real worktree; override with drive_res for specific outcomes.
    dr = {"effective_status": 1, "proc_exit": 0, "stop_reason": None, "failure": "eof",
          "detail": "", "final_message": "ACP-MSG", "model_value": ALIAS,
          "stage": "session/prompt", **(drive_res or {})}

    def _fake_drive(proc, *, prompt_text, cwd, model_alias, frame_sink, deadline_s, **kw):
        drv_cap.update({"prompt_text": prompt_text, "model_alias": model_alias,
                        "deadline_s": deadline_s})
        return dr

    fake_acp = types.ModuleType("fake_kimi_acp")
    fake_acp.drive = _fake_drive

    d.worker_kimi_runtime = _fake_krt
    d.isolated_cmd = _fake_icmd
    d.subprocess.Popen = _fake_Popen
    d.kimi_acp = fake_acp
    if prompt_text is not None:
        fixed = prompt_text
        d.worker_prompt_text = lambda att_dir, lc_arg, n_arg: fixed
    if grade_stub is not None:
        d._grade_phase = grade_stub

    _rec.clear()
    rec = {}
    try:
        d._run_pipeline("SPEC-000-1", "SPEC-000", 1, att, lc,
                        WTE, att / "raw", _finish)
    except _Stop:
        rec = dict(_rec)
    except Exception as e:
        rec = {"exception": str(e)}
    finally:
        d.worker_kimi_runtime = _orig_krt
        d.isolated_cmd = _orig_icmd
        d.subprocess.Popen = _orig_Popen
        d.kimi_acp = _orig_acp
        d._grade_phase = _orig_grade
        d.worker_prompt_text = _orig_wpt

    return rec, cmd_cap, drv_cap


# ---- kimi_acp module-level load (present at dispatch import) -----------------
check("kimi_acp loaded at dispatch import (d.kimi_acp present)",
      hasattr(d, "kimi_acp") and d.kimi_acp is not None)
check("d.kimi_acp.drive is callable", callable(getattr(d.kimi_acp, "drive", None)))


# ---- exact isolated_cmd argv construction ------------------------------------
SMALL_PROMPT = "do the thing"
rec, cmd, drv = run_pipe(prompt_text=SMALL_PROMPT)
check("kimi ACP isolated_cmd argv contains 'acp' subcommand",
      "acp" in cmd.get("argv", []))
check("prompt absent from kimi ACP isolated_cmd argv",
      SMALL_PROMPT not in cmd.get("argv", [])
      and not any(SMALL_PROMPT in str(a) for a in cmd.get("argv", [])))
check("kimi ACP isolated_cmd argv_prefix preserved (fake prefix element present)",
      FAKE_PREFIX[0] in cmd.get("argv", []))
check("kimi ACP isolated_cmd full argv is [prefix..., 'acp']",
      cmd.get("argv") == [*FAKE_PREFIX, "acp"])
check("kimi ACP isolated_cmd unit matches lc worker_unit",
      cmd.get("unit") == lc_base["worker_unit"])
check("kimi ACP isolated_cmd slice_name is attempt_slice(attempt_id)",
      cmd.get("slice_name") == d.attempt_slice("SPEC-000-1"))
check("kimi ACP isolated_cmd env_extra is empty (kimi iso_env_extra, probe A)",
      cmd.get("env_extra") == {})
check("kimi ACP isolated_cmd rw_paths includes worktree and kimi state home",
      str(WTE) in cmd.get("rw_paths", [])
      and "/home/codex-worker/.kimi-code" in cmd.get("rw_paths", []))


# ---- small prompt delivered via drive(), not argv ----------------------------
rec, cmd, drv = run_pipe(prompt_text=SMALL_PROMPT)
check("small prompt passed to drive() verbatim", drv.get("prompt_text") == SMALL_PROMPT)
check("drive() receives correct model alias", drv.get("model_alias") == ALIAS)
check("small prompt not in isolated_cmd argv", SMALL_PROMPT not in cmd.get("argv", []))


# ---- oversized prompt (>MAX_ARG_STRLEN = 131072 bytes) delivered correctly ---
BIG_PROMPT = "x" * 140000   # 140 000 bytes, well above the 131072 ceiling
rec, cmd, drv = run_pipe(prompt_text=BIG_PROMPT)
check("oversized prompt (>131072 bytes) passed to drive() intact",
      drv.get("prompt_text") == BIG_PROMPT)
check("oversized prompt byte length exceeds MAX_ARG_STRLEN",
      len((drv.get("prompt_text") or "").encode()) > 131072)
check("oversized prompt absent from isolated_cmd argv (no argv element > 131072 bytes)",
      not any(len(str(a).encode()) > 131072 for a in cmd.get("argv", [])))


# ---- response correlation: final_message from drive() → grading last_message -
grade_cap = {}
def _grade_cap_stub(attempt_id, spec_id, n, att_dir, lc, wt, raw, finish,
                    worker_adapter, worker_exit, stderr_txt, last_message):
    grade_cap.update({"worker_exit": worker_exit, "last_message": last_message})
    raise _Stop()

rec, cmd, drv = run_pipe(
    drive_res={"effective_status": 0, "proc_exit": 0, "stop_reason": "end_turn",
               "failure": None, "final_message": "CORR-FINAL-MSG"},
    grade_stub=_grade_cap_stub)
check("final_message from drive() reaches _grade_phase as last_message",
      grade_cap.get("last_message") == "CORR-FINAL-MSG")
check("effective_status=0 from drive() reaches _grade_phase as worker_exit=0",
      grade_cap.get("worker_exit") == 0)


# ---- fail-closed: zero-exit incomplete session must not grade as success ------
# C1 regression (amendment 2026-07-18): proc_exit=0 but no end_turn in the session
# → effective_status=1 from drive() → classify_error(1,...) → failed_worker_error.
# This is the core safety invariant: a green process exit that lacks a terminal
# end_turn response is treated as a worker failure, never as a passing grade.
rec, cmd, drv = run_pipe(
    drive_res={"effective_status": 1, "proc_exit": 0, "stop_reason": None, "failure": "eof"})
check("C1 regression: zero-exit incomplete session records failed_worker_error",
      rec.get("status") == "failed_worker_error")
check("C1 regression: zero-exit incomplete session outcome is TERMINAL (never live/success)",
      rec.get("status") in d.TERMINAL)


# ---- fail-closed: malformed frame -------------------------------------------
rec, cmd, drv = run_pipe(
    drive_res={"effective_status": 1, "proc_exit": 1,
               "stop_reason": None, "failure": "malformed_frame"})
check("malformed_frame effective_status=1 records failed_worker_error",
      rec.get("status") == "failed_worker_error")
check("malformed_frame outcome is TERMINAL", rec.get("status") in d.TERMINAL)


# ---- fail-closed: JSON-RPC error response -----------------------------------
rec, cmd, drv = run_pipe(
    drive_res={"effective_status": 1, "proc_exit": 1,
               "stop_reason": None, "failure": "jsonrpc_error"})
check("jsonrpc_error effective_status=1 records failed_worker_error",
      rec.get("status") == "failed_worker_error")
check("jsonrpc_error outcome is TERMINAL", rec.get("status") in d.TERMINAL)


# ---- alias validation at the ACP call site (same contract as build_argv) -----
# A missing alias must refuse launch — never invoke kimi with the raw relay id.
rec, cmd, drv = run_pipe(lc_extra={"cli_aliases": {}})
check("missing alias in ACP path records error_launch",
      rec.get("status") == "error_launch" and rec.get("error_class") == d.ERR_LAUNCH)
check("missing alias error_launch is TERMINAL", rec.get("status") in d.TERMINAL)

# An identity alias (raw id laundered through the map) is equally refused.
rec, cmd, drv = run_pipe(lc_extra={"cli_aliases": {"kimi-k3": "kimi-k3"}})
check("identity alias in ACP path records error_launch (same contract as build_argv)",
      rec.get("status") == "error_launch" and rec.get("error_class") == d.ERR_LAUNCH)

# A non-string alias value is also refused.
rec, cmd, drv = run_pipe(lc_extra={"cli_aliases": {"kimi-k3": 7}})
check("non-string alias in ACP path records error_launch",
      rec.get("status") == "error_launch" and rec.get("error_class") == d.ERR_LAUNCH)

sys.exit(0 if not fails else 1)
PY

if [ $? -eq 0 ]
then echo "PASS kimi_acp_transport.sh"; exit 0
else echo "FAIL kimi_acp_transport.sh"; exit 1; fi
