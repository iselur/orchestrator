#!/usr/bin/env python3
"""Per-row compare-and-set leases."""
from __future__ import annotations

import argparse
import fcntl
import os
import signal
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORCH = ROOT / ".orchestrator"
LEASES = ORCH / "leases"
LOCK = LEASES / ".lock"
FLOOR = LEASES / ".last_now"
MAX_INT = 2**63 - 1


class LeaseError(Exception):
    def __init__(self, message: str, code: int = 1):
        super().__init__(message)
        self.code = code


def _row(row: str) -> str:
    if not row or row in (".", "..") or "/" in row or "\\" in row:
        raise LeaseError("invalid row", 2)
    return row


def _integer(value: str, name: str) -> int:
    try:
        n = int(value, 10)
    except (TypeError, ValueError):
        raise LeaseError(f"{name} must be an integer", 2)
    if n < 0 or n > MAX_INT:
        raise LeaseError(f"{name} is out of range", 2)
    return n


def _session(session: str) -> str:
    if not session or "\n" in session or "\r" in session:
        raise LeaseError("session must be non-empty and one line", 2)
    return session


def _now() -> int:
    raw = os.environ.get("ORCH_LEASE_FAKE_NOW")
    if raw is not None:
        return _integer(raw, "fake clock")
    return int(time.time())


def _read_floor(exclusive: bool) -> int:
    try:
        value = FLOOR.read_text().strip()
    except FileNotFoundError:
        if not exclusive:
            raise LeaseError("clock floor is missing", 1)
        value = str(_now())
        _atomic(FLOOR, value + "\n")
    except OSError as exc:
        raise LeaseError(f"clock floor is unreadable: {exc}", 1)
    floor = _integer(value, "clock floor")
    current = _now()
    if current < floor:
        raise LeaseError("system clock is behind the lease clock floor", 1)
    return current


def _atomic(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        if os.environ.get("ORCH_LEASE_PUBLISH_BARRIER") == "1":
            while not (ORCH / "HALT").exists():
                pass
            raise LeaseError("HALT is present", 9)
        if os.environ.get("ORCH_LEASE_CRASH_AFTER_STAGE") == "1":
            os.kill(os.getpid(), signal.SIGKILL)
        _halt()
        os.replace(name, path)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def _lock(exclusive: bool):
    LEASES.mkdir(parents=True, exist_ok=True)
    fh = LOCK.open("a+")
    fcntl.flock(fh, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
    return fh


def _path(row: str) -> Path:
    return LEASES / _row(row)


def _record(row: str) -> dict | None:
    path = _path(row)
    try:
        text = path.read_text()
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise LeaseError(f"lease record unreadable: {exc}", 1)
    values = {}
    for line in text.splitlines():
        if "=" not in line:
            raise LeaseError("lease record is malformed", 1)
        key, value = line.split("=", 1)
        if key in values:
            raise LeaseError("lease record is malformed", 1)
        values[key] = value
    if set(values) != {"row", "generation", "session", "expiry"}:
        raise LeaseError("lease record schema is invalid", 1)
    if values["row"] != row or not values["session"]:
        raise LeaseError("lease record schema is invalid", 1)
    values["generation"] = _integer(values["generation"], "generation")
    values["expiry"] = _integer(values["expiry"], "expiry")
    return values


def _write(row: str, generation: int, session: str, expiry: int) -> None:
    _halt()
    _atomic(_path(row), f"row={row}\ngeneration={generation}\nsession={session}\nexpiry={expiry}\n")


def _halt() -> None:
    if (ORCH / "HALT").exists():
        raise LeaseError("HALT is present", 9)


def _finish_mutation(now: int) -> None:
    _halt()
    _atomic(FLOOR, f"{now}\n")


def _authorize(record: dict, row: str, generation: int | None, session: str, now: int) -> None:
    if (record["row"], record["session"]) != (row, session):
        raise LeaseError("lease is owned by another session", 1)
    if generation is not None and record["generation"] != generation:
        raise LeaseError("lease generation does not match", 1)
    if record["expiry"] <= now:
        raise LeaseError("lease is expired", 1)


def acquire(row: str, session: str, ttl: str | int) -> dict:
    row = _row(row); session = _session(session); ttl = _integer(str(ttl), "ttl")
    with _lock(True):
        _halt()
        now = _read_floor(True)
        if (ORCH / "deadletters" / row).exists():
            raise LeaseError("row is dead-lettered", 3)
        old = _record(row)
        if old is not None and old["expiry"] > now:
            raise LeaseError("lease is already held", 1)
        generation = 1 if old is None else old["generation"] + 1
        if generation > MAX_INT or now + ttl > MAX_INT:
            raise LeaseError("lease value is out of range", 2)
        _write(row, generation, session, now + ttl)
        _finish_mutation(now)
        return {"row": row, "generation": generation, "session": session, "expiry": now + ttl}


def renew(row: str, generation: str | int, session: str, ttl: str | int) -> dict:
    row = _row(row); generation = _integer(str(generation), "generation")
    session = _session(session); ttl = _integer(str(ttl), "ttl")
    with _lock(True):
        _halt()
        now = _read_floor(True)
        if (ORCH / "deadletters" / row).exists():
            raise LeaseError("row is dead-lettered", 3)
        old = _record(row)
        if old is None:
            raise LeaseError("lease record is missing", 1)
        _authorize(old, row, generation, session, now)
        if now + ttl > MAX_INT:
            raise LeaseError("lease value is out of range", 2)
        _write(row, generation, session, now + ttl)
        _finish_mutation(now)
        return {"row": row, "generation": generation, "session": session, "expiry": now + ttl}


def release(row: str, generation: str | int, session: str) -> None:
    row = _row(row); generation = _integer(str(generation), "generation"); session = _session(session)
    with _lock(True):
        _halt(); now = _read_floor(True)
        old = _record(row)
        if old is None:
            raise LeaseError("lease record is missing", 1)
        _authorize(old, row, generation, session, now)
        _halt()
        _path(row).unlink()
        _atomic(FLOOR, f"{now}\n")


def check(row: str, session: str, generation: str | int | None = None) -> dict:
    row = _row(row); session = _session(session)
    gen = None if generation is None else _integer(str(generation), "generation")
    with _lock(False):
        _halt()
        if (ORCH / "deadletters" / row).exists():
            raise LeaseError("row is dead-lettered", 3)
        now = _read_floor(False)
        old = _record(row)
        if old is None:
            raise LeaseError("lease record is missing", 1)
        _authorize(old, row, gen, session, now)
        return old


def status(row: str) -> dict | None:
    row = _row(row)
    with _lock(False):
        _halt()
        return _record(row)


def main() -> None:
    ap = argparse.ArgumentParser(prog="lease")
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("acquire"); p.add_argument("row"); p.add_argument("session"); p.add_argument("ttl")
    p = sub.add_parser("renew"); p.add_argument("row"); p.add_argument("generation"); p.add_argument("session"); p.add_argument("ttl")
    p = sub.add_parser("release"); p.add_argument("row"); p.add_argument("generation"); p.add_argument("session")
    p = sub.add_parser("check"); p.add_argument("row"); p.add_argument("session"); p.add_argument("generation", nargs="?")
    p = sub.add_parser("status"); p.add_argument("row")
    args = ap.parse_args()
    try:
        if args.command == "acquire": out = acquire(args.row, args.session, args.ttl)
        elif args.command == "renew":
            if not str(args.generation).lstrip("+").isdigit() and str(args.session).lstrip("+").isdigit():
                out = renew(args.row, args.session, args.generation, args.ttl)
            else:
                out = renew(args.row, args.generation, args.session, args.ttl)
        elif args.command == "release":
            if not str(args.generation).lstrip("+").isdigit() and str(args.session).lstrip("+").isdigit():
                release(args.row, args.session, args.generation)
            else:
                release(args.row, args.generation, args.session)
            out = None
        elif args.command == "check":
            if args.generation is not None and not str(args.generation).lstrip("+").isdigit() and str(args.session).lstrip("+").isdigit():
                out = check(args.row, args.generation, args.session)
            else:
                out = check(args.row, args.session, args.generation)
        else: out = status(args.row)
        if args.command == "status" and out is None:
            print("missing")
        elif out is not None:
            print(" ".join(f"{k}={out[k]}" for k in ("row", "generation", "session", "expiry")))
    except LeaseError as exc:
        print(f"LEASE REFUSED: {exc}", file=__import__("sys").stderr)
        raise SystemExit(exc.code)


if __name__ == "__main__":
    main()
