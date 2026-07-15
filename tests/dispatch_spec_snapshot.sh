#!/usr/bin/env bash
# B2 regression — the spec digest is verified once at preflight and frozen into launch.json, but
# the worker prompt, reviewer prompt, and merge gate used to RE-READ the live, mutable spec file.
# Editing specs/<id>.yaml after approval could silently change what the worker builds, what the
# reviewer judges, and what risk_class/needs_network the merge gate reads — while provenance still
# showed the original approved digest.
#
# Fix: freeze the exact approved spec bytes into the attempt at launch (spec-snapshot.yaml,
# recorded digest in launch.json) and read ONLY that snapshot downstream; refuse merge if the live
# spec has drifted from the recorded digest.
#
# Drives the REAL functions (write_spec_snapshot, snapshot_spec_text, cmd_merge) with a stubbed
# `gh`/autonomy seam — no network, no systemd, no quota. Same box-only skip contract as the other
# dispatcher self-tests.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="${ORCH_TEST_PY:-.venv/bin/python}"
if [ ! -x "$PY" ] || ! "$PY" -c 'import yaml, jsonschema' 2>/dev/null; then
  echo "SKIP dispatch_spec_snapshot.sh: .venv/pyyaml/jsonschema absent (dispatcher self-test runs on the box only, not CI)"
  exit 77   # did NOT run — never a pass (T1/R26)
fi

"$PY" - <<'PY'
import importlib.util, json, pathlib, tempfile, types

spec = importlib.util.spec_from_file_location("d", "scripts/dispatch.py")
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails.append(name)

tmp = pathlib.Path(tempfile.mkdtemp())
d.ATTEMPTS = tmp / "attempts"; d.SPECS = tmp / "specs"; d.STATE = tmp / "state"
d.APPROVALS = tmp / "approvals"; d.ESCALATIONS = tmp / "escalations"
for p in (d.ATTEMPTS, d.SPECS, d.STATE, d.APPROVALS, d.ESCALATIONS): p.mkdir(parents=True)
d.HALT = tmp / "nonexistent-halt-marker"

ORIGINAL = (
    "id: SPEC-777\ntitle: original\nrisk_class: low\nneeds_network: false\n"
    "objective: o\nin_scope: ['a/**']\nacceptance_criteria: ['do the real thing']\n"
    "test_command: 'true'\n"
)
(d.SPECS / "SPEC-777.yaml").write_text(ORIGINAL)
approved_digest = d.spec_digest("SPEC-777")

att = d.ATTEMPTS / "SPEC-777" / "1"; att.mkdir(parents=True)

# --- (a) snapshot freezes the approved bytes; later live edits don't reach it ------------------
snap_digest = d.write_spec_snapshot("SPEC-777", att, approved_digest)
check("write_spec_snapshot returns the approved digest", snap_digest == approved_digest)
check("snapshot file holds the exact approved bytes",
      d.spec_snapshot_path(att).read_bytes() == ORIGINAL.encode())
check("snapshot_spec_text returns the approved text pre-edit",
      d.snapshot_spec_text(att) == ORIGINAL)

# Mutate the LIVE spec after "approval": weaken acceptance criteria and flip risk_class high->low
# in spirit (a real attacker would try to slip a high-risk change under a low-risk autonomy grant).
MUTATED = (
    "id: SPEC-777\ntitle: mutated\nrisk_class: high\nneeds_network: true\n"
    "objective: o\nin_scope: ['a/**']\nacceptance_criteria: ['do whatever']\n"
    "test_command: 'true'\n"
)
(d.SPECS / "SPEC-777.yaml").write_text(MUTATED)
live_digest_after_edit = d.spec_digest("SPEC-777")
check("sanity: the live edit actually changed the digest", live_digest_after_edit != approved_digest)

check("worker/reviewer prompt source (snapshot_spec_text) is UNCHANGED by the live edit",
      d.snapshot_spec_text(att) == ORIGINAL)
check("the live spec file itself DID change (proves this is a real edit, not a no-op)",
      d.spec_path("SPEC-777").read_text() == MUTATED)

# A fresh launch attempting to snapshot against the STALE approved digest must fail closed (closes
# the narrow preflight-to-snapshot race window) rather than silently snapshotting the edited spec.
att2 = d.ATTEMPTS / "SPEC-777" / "2"; att2.mkdir(parents=True)
try:
    d.write_spec_snapshot("SPEC-777", att2, approved_digest); race_code = None
except SystemExit as e:
    race_code = e.code
check("write_spec_snapshot refuses when live spec no longer matches the approved digest",
      race_code == 6)
check("a refused snapshot leaves no spec-snapshot.yaml behind",
      not d.spec_snapshot_path(att2).exists())

# --- (b)/(c) cmd_merge: refuse on drift, allow on a matching snapshot/digest --------------------
def setup_merge_attempt(n, launch_extra, spec_text):
    a = d.ATTEMPTS / "SPEC-777" / str(n); a.mkdir(parents=True, exist_ok=True)
    worker_commit = "c" * 40
    (a / "result.json").write_text(json.dumps({
        "status": "passed_pr_opened", "base_sha": "b" * 40,
        "worker_commit": worker_commit, "pr_url": "https://github.com/x/y/pull/42",
    }))
    lc = {"base_branch": d.AUTOMATION_BASE, **launch_extra}
    (a / "launch.json").write_text(json.dumps(lc))
    (d.SPECS / "SPEC-777.yaml").write_text(spec_text)
    return a, worker_commit

class FakeGh:
    """Records gh calls; a working PASS-shaped response for gh pr view / gh pr merge."""
    def __init__(self):
        self.merge_called = False
        self.view_called = False
    def __call__(self, cmd, **kw):
        if cmd[:3] == ["gh", "pr", "view"]:
            self.view_called = True
            return types.SimpleNamespace(returncode=0, stderr="", stdout=json.dumps({
                "state": "OPEN", "isDraft": False, "headRefOid": "c" * 40,
                "baseRefName": d.AUTOMATION_BASE, "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "statusCheckRollup": [{"name": "ci", "conclusion": "SUCCESS"}],
            }))
        if cmd[:3] == ["gh", "pr", "merge"]:
            self.merge_called = True
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

d.load_autonomy = lambda: {"enabled": True, "target_branch": d.AUTOMATION_BASE,
                           "allowed_risk_class": ["low", "default"],
                           "needs_network_allowed": False}
d._base_tip = lambda base: "b" * 40   # base unchanged since review -> not stale

def run_merge(attempt_n):
    fake = FakeGh(); d.run = fake
    try:
        d.cmd_merge(f"SPEC-777-{attempt_n}"); code = None
    except SystemExit as e:
        code = e.code
    return fake, code

# (b) launch.json recorded the ORIGINAL approved digest; live spec is the MUTATED one (edited
# after approval, e.g. to flip risk_class high->low or weaken criteria). Must REFUSE, and must
# never even reach `gh pr view` / `gh pr merge`.
setup_merge_attempt(10, {"spec_digest": approved_digest, "spec_snapshot_digest": approved_digest,
                        "risk_class": "low", "needs_network": False}, MUTATED)
fake, code = run_merge(10)
check("cmd_merge REFUSES when live spec digest != recorded snapshot digest", code == 12)
check("a refused merge never calls gh pr view", not fake.view_called)
check("a refused merge never calls gh pr merge", not fake.merge_called)

# (c) live spec restored to match the recorded digest -> the normal path proceeds and merges.
setup_merge_attempt(11, {"spec_digest": approved_digest, "spec_snapshot_digest": approved_digest,
                        "risk_class": "low", "needs_network": False}, ORIGINAL)
fake, code = run_merge(11)
check("cmd_merge ALLOWS when live spec digest matches the recorded snapshot digest", code is None)
check("a matching digest reaches gh pr view", fake.view_called)
check("a matching digest calls gh pr merge", fake.merge_called)
merged_result = json.loads((d.ATTEMPTS / "SPEC-777" / "11" / "result.json").read_text())
check("merged attempt's result.json records merged:true", merged_result.get("merged") is True)

# (c2) historical attempt: no spec_snapshot_digest/risk_class/needs_network fields recorded (as
# launch.json looked before this fix), and no spec-snapshot.yaml file. Only the pre-existing
# spec_digest field is present. Must not crash, and must still enforce the digest check.
setup_merge_attempt(12, {"spec_digest": approved_digest}, MUTATED)
fake, code = run_merge(12)
check("historical attempt (no snapshot fields) still REFUSES on a live edit", code == 12)
check("historical-attempt refusal never calls gh pr merge", not fake.merge_called)

setup_merge_attempt(13, {"spec_digest": approved_digest}, ORIGINAL)
fake, code = run_merge(13)
check("historical attempt (no snapshot fields) with a matching live spec merges normally",
      code is None and fake.merge_called)

# (d) grant refuses a high-risk spec even when the recorded risk_class (not the live file) says so.
setup_merge_attempt(14, {"spec_digest": approved_digest, "spec_snapshot_digest": approved_digest,
                        "risk_class": "high", "needs_network": False}, ORIGINAL)
fake, code = run_merge(14)
check("recorded risk_class (not the live spec) drives the grant check", code == 12 and not fake.merge_called)

print(f"\n{'PASS' if not fails else 'FAIL'}: B2 spec snapshot ({len(fails)} failed)")
import sys; sys.exit(1 if fails else 0)
PY
