#!/usr/bin/env bash
# B6 (audit codex-audit-2026-07-15, report.md #6 / verification.md H6) — regression test for two
# related bugs in the systemd-unit lifecycle:
#
#   1. An attempt spawns FIVE unit families (worker, spec test, one per installed test, regression
#      base, regression candidate) but `dispatch cancel` stopped only two hand-picked names, leaving
#      the rest running as orphans after the operator believed the attempt was dead.
#   2. Every phase got a FRESH FULL RuntimeMaxSec ceiling instead of sharing one absolute attempt
#      deadline, so total wall-clock could run to several multiples of the configured hard ceiling.
#
# Fix under test: every attempt-owned SYSTEM unit (isolated_run) now joins one systemd slice
# (attempt_slice()); cancel/health/reconcile stop the SLICE, not two unit names; and every phase asks
# for only the time REMAINING to one deadline recorded at launch (remaining_ceiling_s()), never a
# fresh ceiling.
#
# Real systemd side effects are unavailable in CI (and undesirable even on the box for a unit test),
# so this is hermetic: `subprocess.run` (the seam BOTH d.run() and isolated_run() bottom out in) is
# replaced with a fake that RECORDS every command issued and fakes only the systemd/systemctl/sudo
# family, letting git/bash pass through for real. Elapsed time is simulated with an injectable clock
# (d.time.time), never real sleeps. Same box-only skip contract and fake-run style as
# tests/dispatch_gate4.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${ORCH_TEST_PY:-.venv/bin/python}"
if [ ! -x "$PY" ] || ! "$PY" -c 'import yaml, jsonschema' 2>/dev/null; then
  echo "SKIP dispatch_cancel_teardown.sh: .venv/pyyaml/jsonschema absent (dispatcher self-test runs on the box only, not CI)"
  exit 77   # did NOT run — never a pass (T1/R26)
fi

"$PY" - <<'PY'
import importlib.util, json, pathlib, subprocess, tempfile, time as real_time, types

spec = importlib.util.spec_from_file_location("d", "scripts/dispatch.py")
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails.append(name)

# ------------------------------------------------------------------------------------------------
# The seam: isolated_run() calls `subprocess.run` DIRECTLY (not the d.run() wrapper), so the single
# point that reaches EVERY systemd invocation — d.run()'s helper calls (systemctl stop/list-units)
# AND isolated_run()'s systemd-run — is the `subprocess` name inside dispatch.py's own namespace.
# Rebinding d.subprocess (not the real, process-wide `subprocess` module) confines the fake to this
# module: every "systemd-family" command (systemctl / systemd-run / sudo) is recorded and faked
# (never touches a real systemd); everything else (git, bash) passes through to the real
# subprocess.run so the git-repo scaffolding below is exercised for real.
_real_subprocess_run = subprocess.run
calls = []

class FakeClock:
    def __init__(self, start): self.now = start
    def time(self): return self.now
    def advance(self, s): self.now += s

clock = FakeClock(1_700_000_000.0)
PHASE_DURATION_S = 30  # simulated wall-clock cost of one systemd-run phase

def _is_systemd_family(cmd):
    head = cmd[0] if cmd else ""
    return head in ("systemctl", "systemd-run") or head == "sudo"

def fake_run(cmd, **kw):
    cmd = list(cmd)
    calls.append(cmd)
    if _is_systemd_family(cmd):
        if "systemd-run" in cmd:
            clock.advance(PHASE_DURATION_S)  # a phase "ran" — the deadline ticks down for real
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")
    if "stdout" not in kw and "stderr" not in kw and "capture_output" not in kw:
        kw.setdefault("capture_output", True)
        kw.setdefault("text", True)
    return _real_subprocess_run(cmd, **kw)

d.subprocess = types.SimpleNamespace(run=fake_run, PIPE=subprocess.PIPE,
                                     STDOUT=subprocess.STDOUT, DEVNULL=subprocess.DEVNULL)
d.time = types.SimpleNamespace(time=clock.time, sleep=real_time.sleep)

def runtime_max_sec(cmd):
    for tok in cmd:
        if tok.startswith("--property=RuntimeMaxSec="):
            return int(tok.split("=", 2)[-1])
    return None

def slice_of(cmd):
    for tok in cmd:
        if tok.startswith("--slice="):
            return tok.split("=", 1)[1]
    return None

def unit_of(cmd):
    for tok in cmd:
        if tok.startswith("--unit="):
            return tok.split("=", 1)[1]
    return None

# ==================================================================================================
# Group A — isolated_run() threads --slice=<attempt slice> into EVERY unit family it is asked to run
# (the single shared implementation point every attempt-owned call site routes through), and omits
# it when no slice_name is given (the two pre-attempt runtime-probe units, which are not attempt-
# owned and correctly stay out of any attempt's slice).
aid = "SPEC-900-1"
families = {
    "worker": f"codex-worker-{aid}",
    "spec-test": f"codex-test-{aid}",
    "installed-test": f"codex-test-{aid}-mystem",
    "regression-base": f"codex-regbase-{aid}",
    "regression-candidate": f"codex-regcand-{aid}",
}
for label, unit in families.items():
    calls.clear()
    d.isolated_run(unit, ["true"], cwd=None, rw_paths=[], private_network=True, ceiling_s=100,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   slice_name=d.attempt_slice(aid))
    cmd = calls[-1]
    check(f"isolated_run({label}): unit is {unit}", unit_of(cmd) == unit)
    check(f"isolated_run({label}): joins the attempt slice", slice_of(cmd) == d.attempt_slice(aid))
    check(f"isolated_run({label}): honors the given ceiling", runtime_max_sec(cmd) == 100)

calls.clear()
d.isolated_run(f"codex-rtprobe-SPEC-900", ["true"], cwd=None, rw_paths=[], private_network=True,
               ceiling_s=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)  # no slice_name
check("isolated_run(no slice_name given): no --slice= flag is emitted",
      slice_of(calls[-1]) is None)

# ==================================================================================================
# Group B — remaining_ceiling_s(): the pure deadline-arithmetic at the center of the fix. Uses the
# injected clock, never a real sleep.
d0 = clock.now + 1000
check("remaining_ceiling_s: full window", d.remaining_ceiling_s(d0) == 1000)
clock.advance(900)
check("remaining_ceiling_s: decreases with elapsed time", d.remaining_ceiling_s(d0) == 100)
clock.advance(200)  # now 100s past the deadline
check("remaining_ceiling_s: 0 once the deadline has passed", d.remaining_ceiling_s(d0) == 0)
near_deadline = clock.now + 3  # positive but under the floor
check("remaining_ceiling_s: clamps a nearly-spent deadline to MIN_PHASE_CEILING_S",
      d.remaining_ceiling_s(near_deadline) == d.MIN_PHASE_CEILING_S)

# ==================================================================================================
# Group C — run_candidate_test_phases(): a REAL production call site (not a reimplementation),
# driven against a synthetic 2-test policy so we control exactly how many isolated_run calls happen.
# Proves (a) each installed-test unit joins the attempt slice, and (c) each gets only the time
# REMAINING to the one deadline (strictly decreasing across the loop), not a fresh full ceiling.
ctmp = pathlib.Path(tempfile.mkdtemp())
(ctmp / "tests").mkdir()
for name in ("t1.sh", "t2.sh"):
    p = ctmp / "tests" / name
    p.write_text("#!/bin/sh\nexit 0\n"); p.chmod(0o755)
(ctmp / "tests" / "execution-policy.tsv").write_text(
    "tests/t1.sh\tcandidate-isolated\tsynthetic B6 fixture\n"
    "tests/t2.sh\tcandidate-isolated\tsynthetic B6 fixture\n")
d.run(["git", "init", "-q", "-b", "main", str(ctmp)])
d.run(["git", "-C", str(ctmp), "config", "user.email", "t@t"])
d.run(["git", "-C", str(ctmp), "config", "user.name", "t"])
d.run(["git", "-C", str(ctmp), "add", "-A"])
d.run(["git", "-C", str(ctmp), "commit", "-qm", "init"])
installed_commit = d.git("rev-parse", "HEAD", cwd=ctmp)

_orig_ROOT, _orig_EXECUTION_POLICY = d.ROOT, d.EXECUTION_POLICY
_orig_test_runtime_matches = d.test_runtime_matches
_orig_trusted_test_runtime = d.trusted_test_runtime
d.ROOT = ctmp
d.EXECUTION_POLICY = ctmp / "tests" / "execution-policy.tsv"
d.test_runtime_matches = lambda record: True   # bypass the box-specific trusted-runtime probe
d.trusted_test_runtime = lambda: None          # (it also probes ROOT/scripts/requirements.txt)

policy = d.execution_policy(ctmp)
policy["installed_commit"] = installed_commit
catt = ctmp / "att"; (catt / "raw").mkdir(parents=True)
lc = {"execution_policy": policy, "test_unit": f"codex-test-{aid}", "attempt_id": aid,
      "test_runtime": {"root": "/tmp/fake-test-runtime", "python": "/tmp/fake-test-runtime/bin/python"}}

calls.clear()
deadline = clock.now + 200
d.run_candidate_test_phases(lc, ctmp, installed_commit, catt, deadline, [])
test_calls = [c for c in calls if "systemd-run" in c]
check("run_candidate_test_phases: one isolated_run per required test", len(test_calls) == 2)
check("run_candidate_test_phases: every installed-test unit joins the attempt slice",
      all(slice_of(c) == d.attempt_slice(aid) for c in test_calls))
ceilings = [runtime_max_sec(c) for c in test_calls]
check("run_candidate_test_phases: RuntimeMaxSec strictly decreases across the loop "
      f"(not a fresh ceiling each time) {ceilings}", ceilings[0] > ceilings[1])
check("run_candidate_test_phases: the SAME deadline is spent down, not reset "
      f"(delta == simulated phase cost) {ceilings}", ceilings[0] - ceilings[1] == PHASE_DURATION_S)

# Refusal case: the deadline has already passed before this phase — must NOT start a unit.
calls.clear()
past_deadline = clock.now - 500
result = d.run_candidate_test_phases(lc, ctmp, installed_commit, catt, past_deadline, [])
check("run_candidate_test_phases: refuses to start a phase past a spent deadline (no isolated_run)",
      not any("systemd-run" in c for c in calls))
statuses = [o["status"] for obs in result["tests"].values() for o in obs["observations"][-1:]]
check("run_candidate_test_phases: a refused phase is graded FAIL, never silently skipped",
      statuses and all(s == "FAIL" for s in statuses))
log1 = (catt / "raw" / "candidate-isolated-t1.log").read_text()
check("run_candidate_test_phases: the log names the exhausted deadline as the reason",
      "deadline exhausted" in log1)

d.ROOT, d.EXECUTION_POLICY = _orig_ROOT, _orig_EXECUTION_POLICY
d.test_runtime_matches = _orig_test_runtime_matches
d.trusted_test_runtime = _orig_trusted_test_runtime

# ==================================================================================================
# Group D — run_regression_gate(): the OTHER real production call site, driven against a real temp
# git repo (same fixture shape as tests/dispatch_gate4.sh) with iso=True so it actually reaches
# isolated_run for both the base and candidate runs. Proves both share the attempt slice and the
# candidate run gets less remaining time than the base run (same deadline, real elapsed simulated
# time in between) — plus the refusal case when the deadline is spent between the two runs.
rtmp = pathlib.Path(tempfile.mkdtemp())
rrepo = rtmp / "r"
d.run(["git", "init", "-qb", "main", str(rrepo)])
d.run(["git", "-C", str(rrepo), "config", "user.email", "t@t"])
d.run(["git", "-C", str(rrepo), "config", "user.name", "t"])
(rrepo / "calc.py").write_text("def add(a, b):\n    return a - b  # bug\n")
d.run(["git", "-C", str(rrepo), "add", "-A"])
d.run(["git", "-C", str(rrepo), "commit", "-qm", "base(buggy)"])
rbase = d.git("rev-parse", "HEAD", cwd=rrepo)
(rrepo / "calc.py").write_text("def add(a, b):\n    return a + b\n")
(rrepo / "test_reg.py").write_text("from calc import add\nassert add(2, 2) == 4\nprint('ok')\n")
d.run(["git", "-C", str(rrepo), "add", "-A"])
d.run(["git", "-C", str(rrepo), "commit", "-qm", "fix+test"])
rcand = d.git("rev-parse", "HEAD", cwd=rrepo)
raid = "SPEC-901-1"
rcand_wt = rtmp / raid
d.run(["git", "-C", str(rrepo), "worktree", "add", "--quiet", "--detach", str(rcand_wt), rcand])

_orig_wtr, _orig_git, _orig_gwa = d.worktree_root, d.git, d.grant_worker_acl
d.worktree_root = lambda *a, **k: rtmp
def _tgit(*a, **k):
    k.setdefault("cwd", rrepo)
    return _orig_git(*a, **k)
d.git = _tgit
d.grant_worker_acl = lambda wt: None   # not under test here — B6 is the slice/deadline, not ACLs
_orig_run = d.run
def _trun(cmd, **k):
    if cmd[:2] == ["git", "worktree"]:
        k.setdefault("cwd", str(rrepo))
    return _orig_run(cmd, **k)
d.run = _trun

ratt = rtmp / "att"; ratt.mkdir()
rlc = {"regression_command": "python3 test_reg.py", "regression_test_paths": ["test_reg.py"],
       "base_sha": rbase, "attempt_id": raid}

calls.clear()
r_deadline = clock.now + 200
d.run_regression_gate(rlc, rcand_wt, rcand, ratt, iso=True, deadline_ts=r_deadline)
reg_calls = [c for c in calls if "systemd-run" in c]
check("run_regression_gate: exactly base + candidate isolated_run calls", len(reg_calls) == 2)
check("run_regression_gate: both regression units join the attempt slice",
      all(slice_of(c) == d.attempt_slice(raid) for c in reg_calls))
check("run_regression_gate: base unit is codex-regbase-<aid>",
      unit_of(reg_calls[0]) == f"codex-regbase-{raid}")
check("run_regression_gate: candidate unit is codex-regcand-<aid>",
      unit_of(reg_calls[1]) == f"codex-regcand-{raid}")
reg_ceilings = [runtime_max_sec(c) for c in reg_calls]
check(f"run_regression_gate: candidate run gets LESS remaining time than base (same deadline) "
      f"{reg_ceilings}", reg_ceilings[1] < reg_ceilings[0])

# Refusal case: deadline already spent before the candidate run starts.
calls.clear()
r_deadline2 = clock.now + (PHASE_DURATION_S // 2)  # enough for base to appear to start, not candidate
reg2 = d.run_regression_gate(rlc, rcand_wt, rcand, ratt, iso=True, deadline_ts=r_deadline2)
check("run_regression_gate: refuses the candidate run once the deadline is spent",
      reg2["candidate_exit"] is None and "deadline exhausted" in reg2["reason"])

d.worktree_root, d.git, d.grant_worker_acl, d.run = _orig_wtr, _orig_git, _orig_gwa, _orig_run

# ==================================================================================================
# Group E — cmd_cancel(): the REAL operator-facing command. Before B6 this stopped only two
# hand-picked unit names; it must now stop the whole attempt SLICE (which is where the suffixed
# installed-test and both regression units actually live) as well as the outer pipeline unit, and
# report the post-teardown unit listing.
etmp = pathlib.Path(tempfile.mkdtemp())
d.STATE = etmp / "state"; d.STATE.mkdir()
eaid = "SPEC-902-1"
espec, en = d.parse_attempt_id(eaid)
d.write_state(espec, {"attempt_id": eaid, "spec_id": espec, "attempt": en, "status": "running",
                      "unit": d.unit_name(espec, en)})

calls.clear()
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    d.cmd_cancel(eaid)
out = json.loads(buf.getvalue())

slice_stops = [c for c in calls if c[:3] == ["sudo", "-n", "systemctl"] and c[3:4] == ["stop"]]
check("cmd_cancel: stops the attempt SLICE (not just worker+test unit names)",
      any(c[-1] == d.attempt_slice(eaid) for c in slice_stops))
outer_stops = [c for c in calls if c[:3] == ["systemctl", "--user", "stop"]]
check("cmd_cancel: also stops the outer --user pipeline unit",
      any(c[-1] == d.unit_name(espec, en) for c in outer_stops))
check("cmd_cancel: reports the post-teardown unit listing", "remaining_units" in out)
check("cmd_cancel: verification found nothing left running (fake systemctl reports empty)",
      out["remaining_units"] == [])
st = d.read_state(espec)
check("cmd_cancel: state moves to interrupted/cancelled", st["status"] == "interrupted"
      and st["error_class"] == "cancelled")

# ==================================================================================================
# Group F — cmd_reconcile(): when the outer unit is found dead while state was still LIVE (crash,
# box restart, or the outer unit's own RuntimeMaxSec firing), the attempt's system units are
# independent of it and can still be running — reconcile must tear down the slice too, not just
# relabel state and walk away from an orphan.
ftmp = pathlib.Path(tempfile.mkdtemp())
d.STATE = ftmp / "state"; d.STATE.mkdir()
faid = "SPEC-903-1"
fspec, fn = d.parse_attempt_id(faid)
d.write_state(fspec, {"attempt_id": faid, "spec_id": fspec, "attempt": fn, "status": "running",
                      "unit": d.unit_name(fspec, fn)})

calls.clear()
buf2 = io.StringIO()
with contextlib.redirect_stdout(buf2):
    d.cmd_reconcile()  # fake systemctl show returns nothing -> unit reads as inactive -> "gone"
reconcile_slice_stops = [c for c in calls
                         if c[:3] == ["sudo", "-n", "systemctl"] and c[3:4] == ["stop"]
                         and c[-1] == d.attempt_slice(faid)]
check("cmd_reconcile: an outer unit found dead while LIVE also stops the attempt slice",
      len(reconcile_slice_stops) == 1)
fst = d.read_state(fspec)
check("cmd_reconcile: state moves to interrupted", fst["status"] == "interrupted")

print()
print(f"{'FAIL' if fails else 'PASS'}: dispatch_cancel_teardown.sh ({len(fails)} failed)")
import sys as _sys
_sys.exit(1 if fails else 0)
PY
