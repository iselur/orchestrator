#!/usr/bin/env python3
"""Deterministic lease, intake-fence, and dispatcher authority drills."""
from __future__ import annotations

import importlib.util
import json
import multiprocessing
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import lease


def fail(message):
    raise AssertionError(message)


def expect(exc, fn, code=None):
    try:
        fn()
    except exc as err:
        if code is not None and getattr(err, "code", None) != code:
            fail(f"expected exit/error code {code}, got {getattr(err, 'code', None)}")
        return err
    fail(f"expected {exc.__name__}")


def setup():
    global td
    td = Path(tempfile.mkdtemp(prefix="lease-drill-"))
    lease.ORCH = td / ".orchestrator"
    lease.LEASES = lease.ORCH / "leases"
    lease.LOCK = lease.LEASES / ".lock"
    lease.FLOOR = lease.LEASES / ".last_now"
    os.environ["ORCH_LEASE_FAKE_NOW"] = "100"
    os.environ.pop("ORCH_LEASE_CRASH_AFTER_STAGE", None)
    os.environ.pop("ORCH_LEASE_PUBLISH_BARRIER", None)


def basic_drills():
    got = lease.acquire("R80", "s1", 20)
    assert got == {"row": "R80", "generation": 1, "session": "s1", "expiry": 120}
    expect(lease.LeaseError, lambda: lease.acquire("R80", "s2", 20))
    expect(lease.LeaseError, lambda: lease.renew("R80", 1, "s2", 20))
    expect(lease.LeaseError, lambda: lease.release("R80", 1, "s2"))
    lease.LEASES.joinpath("R80").write_text("row=R80\ngeneration=1\nsession=s1\n")
    expect(lease.LeaseError, lambda: lease.check("R80", "s1"))
    for text in ("", "row=R80\ngeneration=1\nsession=s1\nexpiry=no\n",
                 "row=R80\ngeneration=1\nsession=s1\nexpiry=110\nextra=x\n"):
        lease.LEASES.joinpath("R80").write_text(text)
        expect(lease.LeaseError, lambda: lease.check("R80", "s1"))
    lease.LEASES.joinpath("R80").write_text("row=R80\ngeneration=1\nsession=s1\nexpiry=110\n")
    lease.FLOOR.unlink()
    expect(lease.LeaseError, lambda: lease.check("R80", "s1"))
    lease.FLOOR.mkdir()
    expect(lease.LeaseError, lambda: lease.check("R80", "s1"))
    shutil.rmtree(lease.FLOOR)
    lease.FLOOR.write_text("100\n")
    os.environ["ORCH_LEASE_FAKE_NOW"] = "99"
    expect(lease.LeaseError, lambda: lease.check("R80", "s1"))
    os.environ["ORCH_LEASE_FAKE_NOW"] = "100"
    os.environ["ORCH_LEASE_FAKE_NOW"] = "130"
    got = lease.acquire("R80", "s2", 20)
    assert got["generation"] == 2
    expect(lease.LeaseError, lambda: lease.renew("R80", 1, "s1", 20))
    expect(lease.LeaseError, lambda: lease.release("R80", 1, "s1"))
    os.environ["ORCH_LEASE_FAKE_NOW"] = "130"
    (lease.ORCH / "deadletters").mkdir(exist_ok=True)
    (lease.ORCH / "deadletters" / "R86").write_text("dead")
    expect(lease.LeaseError, lambda: lease.acquire("R86", "s1", 10), 3)
    expect(lease.LeaseError, lambda: lease.acquire("R87", "s1", "-1"), 2)
    os.environ["ORCH_LEASE_FAKE_NOW"] = "100"


def crash_and_halt_drills():
    lease.LEASES.mkdir(parents=True, exist_ok=True)
    lease.FLOOR.write_text("100\n")
    lease.LEASES.joinpath("R81").write_text("row=R81\ngeneration=1\nsession=old\nexpiry=150\n")
    pid = os.fork()
    if pid == 0:
        os.environ["ORCH_LEASE_CRASH_AFTER_STAGE"] = "1"
        try:
            lease.renew("R81", 1, "old", 20)
        except BaseException:
            pass
        os._exit(0)
    os.waitpid(pid, 0)
    assert "expiry=150" in lease.LEASES.joinpath("R81").read_text()
    (lease.ORCH / "HALT").write_text("stop")
    expect(lease.LeaseError, lambda: lease.acquire("R82", "s1", 10), 9)
    (lease.ORCH / "HALT").unlink()
    os.environ["ORCH_LEASE_PUBLISH_BARRIER"] = "1"
    pid = os.fork()
    if pid == 0:
        try:
            lease.acquire("R83", "s1", 10)
        except BaseException:
            pass
        os._exit(0)
    # The barrier is deliberately held between stage and os.replace; HALT makes it abort.
    while not list(lease.LEASES.glob(".R83.*")):
        names = list(lease.LEASES.glob(".R83.*"))
        if names:
            break
    (lease.ORCH / "HALT").write_text("stop")
    os.waitpid(pid, 0)
    assert not lease.LEASES.joinpath("R83").exists()
    os.environ.pop("ORCH_LEASE_PUBLISH_BARRIER", None)
    (lease.ORCH / "HALT").unlink()


def _race_worker(barrier, out):
    barrier.wait()
    try:
        lease.acquire("R84", str(os.getpid()), 50)
        out.put(1)
    except lease.LeaseError:
        out.put(0)


def race_drill():
    barrier = multiprocessing.Barrier(8)
    out = multiprocessing.Queue()
    ps = [multiprocessing.Process(target=_race_worker, args=(barrier, out)) for _ in range(8)]
    for p in ps: p.start()
    for p in ps: p.join(10)
    results = [out.get(timeout=2) for _ in ps]
    assert sum(results) == 1
    assert lease.status("R84")["generation"] == 1


def intake_drill():
    root = td / "intake-root"
    (root / "scripts").mkdir(parents=True)
    (root / ".orchestrator").mkdir()
    for name in ("intake", "lease", "lease.py"):
        shutil.copy2(ROOT / "scripts" / name, root / "scripts" / name)
    (root / "scripts" / "intake").chmod(0o755)
    (root / "scripts" / "lease").chmod(0o755)
    env = {**os.environ, "ORCH_LEASE_FAKE_NOW": "100", "ORCH_LEASE_SESSION": "owner"}
    row = subprocess.check_output([str(root / "scripts/intake"), "-g", "goal", "-d", "done when tested"], cwd=root, env=env, text=True).strip()
    subprocess.check_call([str(root / "scripts/lease"), "acquire", row, "other", "50"], cwd=root, env=env)
    for action in ("close", "observe"):
        args = [str(root / "scripts/intake"), action, row, "owner approved evidence"]
        assert subprocess.run(args, cwd=root, env=env).returncode == 1
    (root / ".orchestrator/deadletters").mkdir()
    (root / ".orchestrator/deadletters" / row).write_text("dead")
    assert subprocess.run([str(root / "scripts/intake"), "close", row, "evidence"], cwd=root, env=env).returncode == 3
    (root / ".orchestrator/deadletters" / row).unlink()
    subprocess.check_call([str(root / "scripts/lease"), "release", row, "1", "other"], cwd=root, env=env)
    subprocess.check_call([str(root / "scripts/intake"), "close", row, "tests pass in run 1"], cwd=root, env=env)


def load_dispatch():
    spec = importlib.util.spec_from_file_location("dispatch_lease_drill", ROOT / "scripts/dispatch.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def dispatch_lease_drills():
    d = load_dispatch()
    d.ORCH = td / ".orchestrator"
    d.ATTEMPTS = d.ORCH / "attempts"
    d.HALT = d.ORCH / "HALT"
    d.AUTONOMY = d.ORCH / "AUTONOMY.json"
    d.AUTONOMY_LOCAL = d.ORCH / "AUTONOMY.local.json"
    d.load_autonomy = lambda: {"enabled": True}
    d.isolation_available = lambda: True
    d.preflight = lambda sid: {"spec": {}, "digest": "x", "approval": {}, "spec_bytes": b""}
    expect(SystemExit, lambda: d.cmd_launch("SPEC-025"), 12)

    lease.acquire("R85", "dispatch", 50)
    approval = {"intake_row": "R85", "lease_generation": 1, "lease_session": "dispatch"}
    d.preflight = lambda sid: {"spec": {}, "digest": "x", "approval": approval, "spec_bytes": b""}
    d.load_model_config = lambda: (_ for _ in ()).throw(RuntimeError("stop after launch lease"))
    expect(RuntimeError, lambda: d.cmd_launch("SPEC-025"))

    att = d.ATTEMPTS / "SPEC-025" / "1"
    (att / "raw").mkdir(parents=True)
    (att / "launch.json").write_text(json.dumps({"lease": approval, "worker_mode": "external-cli"}))
    expect(SystemExit, lambda: d.cmd_continue("SPEC-025-1"), 6)  # live lease authorized first
    os.environ["ORCH_LEASE_FAKE_NOW"] = "200"
    lease.acquire("R85", "successor", 50)
    expect(SystemExit, lambda: d.cmd_continue("SPEC-025-1"), 6)  # stale tuple is refused
    os.environ["ORCH_LEASE_FAKE_NOW"] = "100"
    merge_att = d.ATTEMPTS / "SPEC-025" / "2"
    merge_att.mkdir(parents=True)
    (merge_att / "launch.json").write_text(json.dumps({"lease": {"intake_row": "R85", "lease_generation": 2, "lease_session": "successor"}}))
    (merge_att / "result.json").write_text(json.dumps({"status": "passed_pr_opened"}))
    os.environ["ORCH_LEASE_FAKE_NOW"] = "200"
    expect(SystemExit, lambda: d.cmd_merge("SPEC-025-2"), 12)  # authorized lease, later merge gate refuses


def main():
    setup()
    try:
        basic_drills(); crash_and_halt_drills(); race_drill(); intake_drill(); dispatch_lease_drills()
    finally:
        shutil.rmtree(td, ignore_errors=True)
    print("PASS lease_cases.py")


if __name__ == "__main__":
    main()
