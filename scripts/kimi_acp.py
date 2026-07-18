#!/usr/bin/env python3
"""Minimal stdlib ACP client for the isolated kimi worker transport (PLAN-009).

drive() speaks newline-delimited JSON-RPC 2.0 over an already-open child's stdin/stdout —
in production the hardened `sudo systemd-run --pipe` chain built by dispatch.isolated_cmd,
in tests a fake stdio peer. The prompt travels inside a frame, never in argv, so it has no
MAX_ARG_STRLEN ceiling (R97).

Fail-closed contract (PLAN-009 amendment 2026-07-18): the EFFECTIVE status is nonzero
whenever the session lacked a validated stopReason:end_turn terminal response — malformed
frame (anything but a jsonrpc-2.0 object of valid shape), JSON-RPC error, unexpected
response id, agent-to-client request, unconfirmed model read-back, wrong stop reason, EOF,
write stall, deadline — regardless of the child's own exit code, so a zero-exit incomplete
session can never grade as success. A prompt response only counts once the prompt frame
was fully written — a peer answering a prompt it never read fails closed. The child is
killed only when still alive. Every raw stdout line reaches the frame sink BEFORE parsing.

The model must be selected in-band: a fresh ACP session defaults to K2.7, so drive()
issues session/set_model with the frozen alias and requires a config_option_update
read-back echoing it — for that session, RECEIVED after the set_model response frame,
the transaction fence: the peer emits that response only after fully reading set_model,
the reader stamps every line with a receive-order seq before any sink I/O, and the fence
seq is taken in the consuming thread, so no stale, sink-held, or written-while-pending
update can ever confirm and no fresh one is racily rejected. The CLI emits its read-back
before that response and again after set_mode, so the wait sits after set_mode — before
any prompt is sent (amendment 2026-07-18 (2)). Session mode
is set to yolo — the same self-approval the -p transport had built in; the hardened unit
remains the sole confinement.
"""

import json
import queue
import subprocess
import threading
import time

PROTOCOL_VERSION = 1
# How long after set_mode resolves to wait for a post-fence config_option_update
# read-back (observed with set_mode's update; the window only bounds a misbehaving peer).
MODEL_CONFIRM_WINDOW_S = 30
SHUTDOWN_WAIT_S = 30


class ProtocolFailure(Exception):
    def __init__(self, reason, detail=""):
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason
        self.detail = detail


def _frame(obj):
    return (json.dumps(obj, separators=(",", ":")) + "\n").encode()


class _Session:
    def __init__(self, proc, frame_sink):
        self.proc = proc
        self.q = queue.SimpleQueue()
        self.writer = None
        self.writer_failure = None
        self.next_id = 0
        self.chunks = []
        self.sid = None
        self.model_value = None
        self.model_watermark = float("inf")  # no read-back confirms before the fence
        self.rx_seq = 0  # lines received, stamped BEFORE any sink I/O or queueing
        self.cur_seq = 0

        def read():
            try:
                for line in proc.stdout:
                    self.rx_seq += 1
                    seq = self.rx_seq
                    frame_sink.write(line)
                    frame_sink.flush()
                    self.q.put((seq, line))
            except OSError:
                pass
            self.q.put(None)

        threading.Thread(target=read, daemon=True).start()

    def _send(self, obj):
        try:
            self.proc.stdin.write(_frame(obj))
            self.proc.stdin.flush()
        except OSError as e:
            raise ProtocolFailure("write_failed", str(e))

    def _note(self, msg):
        if msg.get("method") != "session/update":
            return  # unknown notification: raw-recorded by the reader, otherwise ignored
        params = msg.get("params")
        if not isinstance(params, dict):
            raise ProtocolFailure("malformed_frame", "session/update params not an object")
        # every field this driver reads is type-validated per the ACP schema for EVERY
        # session/update, before the session filter — consumption is gated, never validation
        sid = params.get("sessionId")
        if not isinstance(sid, str):
            raise ProtocolFailure("malformed_frame", "sessionId not a string")
        update = params.get("update")
        if not isinstance(update, dict):
            raise ProtocolFailure("malformed_frame", "session/update update not an object")
        kind = update.get("sessionUpdate")
        if not isinstance(kind, str):
            raise ProtocolFailure("malformed_frame", "sessionUpdate not a string")
        mine = self.sid is not None and sid == self.sid
        if kind == "agent_message_chunk":
            content = update.get("content")
            if not isinstance(content, dict):
                raise ProtocolFailure("malformed_frame", "chunk content not an object")
            ctype = content.get("type")
            if not isinstance(ctype, str):
                raise ProtocolFailure("malformed_frame", "chunk content type not a string")
            if ctype == "text":
                text = content.get("text")
                if not isinstance(text, str):
                    raise ProtocolFailure("malformed_frame", "chunk text not a string")
                if mine:
                    self.chunks.append(text)
        elif kind == "config_option_update":
            opts = update.get("configOptions")
            if not isinstance(opts, list):
                raise ProtocolFailure("malformed_frame", "configOptions not a list")
            for opt in opts:
                if not isinstance(opt, dict) or not isinstance(opt.get("id"), str):
                    raise ProtocolFailure("malformed_frame", "configOption id not a string")
                if opt["id"] == "model":
                    value = opt.get("currentValue")
                    if not isinstance(value, str):
                        raise ProtocolFailure("malformed_frame",
                                              "model currentValue not a string")
                    if mine and self.cur_seq > self.model_watermark:
                        self.model_value = value

    def _handle(self, item):
        """Parse and validate one queued (seq, raw line) item; notifications are processed
        for side effects. Agent-to-client requests and every malformed shape fail closed."""
        if item is None:
            raise ProtocolFailure("eof")
        self.cur_seq, line = item
        try:
            msg = json.loads(line)
        except ValueError:
            raise ProtocolFailure("malformed_frame", line[:200].decode("utf-8", "replace"))
        if not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0":
            raise ProtocolFailure("malformed_frame", "not a jsonrpc-2.0 object")
        if "method" in msg:
            if not isinstance(msg["method"], str):
                raise ProtocolFailure("malformed_frame", "method not a string")
            if "params" in msg and not isinstance(msg["params"], dict):
                raise ProtocolFailure("malformed_frame", "params not an object")
            if "id" in msg:
                # no fs/terminal/permission capability was offered; refuse and fail closed
                # (skip the reply if the prompt writer still owns stdin)
                if self.writer is None or not self.writer.is_alive():
                    self._send({"jsonrpc": "2.0", "id": msg["id"],
                                "error": {"code": -32601,
                                          "message": "client capability not offered"}})
                raise ProtocolFailure("agent_request", str(msg.get("method")))
            self._note(msg)
        else:
            # JSON-RPC response ids are strings, numbers, or null — never booleans, which
            # Python would otherwise equate with our integer ids (True == 1)
            rid = msg.get("id")
            if isinstance(rid, bool) or not isinstance(rid, (str, int, float, type(None))):
                raise ProtocolFailure("malformed_frame", "invalid response id type")
        return msg

    def _recv(self, until_ts, timeout_reason):
        """Return the next parsed frame; notifications are processed for side effects and
        returned too (callers skip or await them)."""
        while True:
            remaining = until_ts - time.monotonic()
            if remaining <= 0:
                if self.writer is not None and self.writer.is_alive():
                    raise ProtocolFailure("write_stall")
                raise ProtocolFailure(timeout_reason)
            try:
                item = self.q.get(timeout=remaining)
            except queue.Empty:
                continue
            return self._handle(item)

    def request(self, method, params, until_ts, big=False, arm_model=False):
        self.next_id += 1
        rid = self.next_id
        frame = {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}
        if big:
            # the prompt frame can exceed the pipe buffer; a blocking write here would
            # deadlock against an unread stdout (N4) — write concurrently with reading
            self.writer = threading.Thread(target=lambda: self._send_quiet(frame), daemon=True)
            self.writer.start()
        else:
            self._send(frame)
        while True:
            msg = self._recv(until_ts, "deadline")
            if "method" in msg:
                continue
            if msg.get("id") != rid:
                raise ProtocolFailure("unexpected_response_id", repr(msg.get("id")))
            if "error" in msg:
                raise ProtocolFailure("jsonrpc_error", json.dumps(msg["error"])[:300])
            result = msg.get("result")
            if not isinstance(result, dict):
                raise ProtocolFailure("malformed_frame", "non-object result")
            if big:
                # a response is only valid once the request actually reached the peer:
                # a peer answering a prompt it never finished reading fails closed
                self.writer.join(max(0.0, until_ts - time.monotonic()))
                if self.writer.is_alive():
                    raise ProtocolFailure("write_stall")
                if self.writer_failure is not None:
                    raise self.writer_failure
            if arm_model:
                # this response is the transaction fence: the peer emits it only after
                # fully reading set_model, so only frames received after it can reflect
                # the new model — anything earlier (stale, sink-held, or received while
                # the write was pending) carries a smaller seq and cannot confirm, and
                # the fence seq is this thread's cur_seq, so no sampling race either way
                self.model_watermark = self.cur_seq
            return result

    def _send_quiet(self, frame):
        try:
            self._send(frame)
        except ProtocolFailure as e:
            self.writer_failure = e  # surfaces via the post-response writer check


def drive(proc, *, prompt_text, cwd, model_alias, frame_sink, deadline_s, mode_id="yolo"):
    """Run one full ACP prompt session against proc. Returns a dict with effective_status
    (0 only for a validated end_turn session AND child exit 0), proc_exit, stop_reason,
    failure (reason string or None), final_message (concatenated agent_message_chunk text),
    and model_value (last config_option_update read-back)."""
    deadline_ts = time.monotonic() + deadline_s
    s = _Session(proc, frame_sink)
    failure = detail = None
    stop_reason = None
    try:
        init = s.request("initialize",
                         {"protocolVersion": PROTOCOL_VERSION,
                          "clientCapabilities": {"fs": {"readTextFile": False,
                                                        "writeTextFile": False}}},
                         deadline_ts)
        pv = init.get("protocolVersion")
        if isinstance(pv, bool) or pv != PROTOCOL_VERSION:
            raise ProtocolFailure("protocol_version", repr(pv))
        new = s.request("session/new", {"cwd": cwd, "mcpServers": []}, deadline_ts)
        sid = new.get("sessionId")
        if not isinstance(sid, str) or not sid:
            raise ProtocolFailure("no_session_id")
        s.sid = sid
        # only a read-back for THIS session received after the set_model response frame
        # confirms it (arm_model); the CLI emits its read-back before that response and
        # again after set_mode, so the confirmation wait sits after set_mode
        s.request("session/set_model", {"sessionId": sid, "modelId": model_alias},
                  deadline_ts, arm_model=True)
        s.request("session/set_mode", {"sessionId": sid, "modeId": mode_id}, deadline_ts)
        confirm_ts = min(deadline_ts, time.monotonic() + MODEL_CONFIRM_WINDOW_S)
        while s.model_value != model_alias:
            msg = s._recv(confirm_ts, "model_unconfirmed")
            if "method" not in msg:
                raise ProtocolFailure("unexpected_response_id", repr(msg.get("id")))
        result = s.request("session/prompt",
                           {"sessionId": sid,
                            "prompt": [{"type": "text", "text": prompt_text}]},
                           deadline_ts, big=True)
        stop_reason = result.get("stopReason")
        if stop_reason != "end_turn":
            raise ProtocolFailure("stop_reason", repr(stop_reason))
    except ProtocolFailure as e:
        failure, detail = e.reason, e.detail

    if failure is None:
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc_exit = proc.wait(
                timeout=max(0.1, min(SHUTDOWN_WAIT_S, deadline_ts - time.monotonic())))
        except subprocess.TimeoutExpired:
            failure = "no_exit"
            proc.kill()
            proc_exit = proc.wait()
    else:
        if proc.poll() is None:
            proc.kill()
        try:
            proc.stdin.close()
        except OSError:
            pass
        proc_exit = proc.wait()

    if failure is None and proc_exit == 0:
        effective = 0
    elif isinstance(proc_exit, int) and proc_exit != 0:
        effective = proc_exit
    else:
        effective = 1
    return {"effective_status": effective, "proc_exit": proc_exit,
            "stop_reason": stop_reason, "failure": failure, "detail": detail,
            "final_message": "".join(s.chunks), "model_value": s.model_value}


def _main():
    """Operator-side check runner (scripts/kimi-acp-check.sh): drives one case through the
    EXACT production hardened envelope (dispatch.isolated_cmd) with our stdio attached."""
    import argparse
    import importlib.util
    import os
    from pathlib import Path

    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True, choices=["smoke", "big", "negative"])
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--raw-dir", required=True)
    ap.add_argument("--prompt-bytes", type=int, default=156956)
    ap.add_argument("--ceiling", type=int, default=900)
    args = ap.parse_args()

    spec = importlib.util.spec_from_file_location(
        "dispatch", Path(__file__).resolve().parent / "dispatch.py")
    dispatch = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dispatch)

    rt = dispatch.worker_kimi_runtime()
    if rt is None:
        print("SKIP: no trusted kimi runtime for the worker")
        raise SystemExit(77)
    argv_prefix, binds, _real = rt
    aliases = json.loads(
        (Path(__file__).resolve().parent / "models.json").read_text()).get("cli_aliases") or {}
    alias = aliases.get("kimi-k3")
    if not isinstance(alias, str) or not alias or alias == "kimi-k3":
        print("FAIL: no distinct cli alias for kimi-k3 in scripts/models.json")
        raise SystemExit(1)

    tag = f"ACP-{args.case.upper()}-{os.getpid()}"
    if args.case == "smoke":
        prompt = (f"Create a file named acp-smoke.txt in the current directory containing "
                  f"exactly one line: {tag}\nThen reply with only: WROTE {tag}")
    elif args.case == "big":
        filler = ("The line below is inert padding for a transport-size proof; "
                  "do not analyze it.\n" + "x" * 4000 + "\n")
        prompt = f"Reply with only: {tag} OK\n"
        while len(prompt.encode()) < args.prompt_bytes:
            prompt += filler
        prompt += f"End of padding. Reply with only: {tag} OK"
    else:
        prompt = "unused"

    raw = Path(args.raw_dir)
    raw.mkdir(parents=True, exist_ok=True)
    cmd = dispatch.isolated_cmd(
        unit=f"kimiacp-{args.case}-{os.getpid()}", argv=[*argv_prefix, "acp"],
        cwd=args.workdir,
        rw_paths=[args.workdir, str(dispatch.WORKER_HOME / ".kimi-code")],
        private_network=False, ceiling_s=args.ceiling, binds=binds)
    (raw / "argv.json").write_text(json.dumps(cmd, indent=1))
    if any(tag in el for el in cmd):
        print("FAIL: prompt material leaked into argv")
        raise SystemExit(1)

    model = alias if args.case != "negative" else "kimi-code/does-not-exist-acp-check"
    with open(raw / "worker-stderr.txt", "wb") as errf, \
            open(raw / "events.jsonl", "wb") as sink:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=errf)
        res = drive(proc, prompt_text=prompt, cwd=args.workdir, model_alias=model,
                    frame_sink=sink, deadline_s=args.ceiling)

    res["case"] = args.case
    res["tag"] = tag
    res["prompt_bytes"] = len(prompt.encode())
    print(json.dumps({k: v for k, v in res.items() if k != "final_message"}))
    print(f"final_message: {res['final_message'][:400]}")

    if args.case == "negative":
        # model_value None proves the error predates any confirmed model: the prompt is
        # only ever sent after confirmation, so this error cannot be a prompt error
        ok = (res["effective_status"] != 0 and res["failure"] == "jsonrpc_error"
              and res["model_value"] is None and res["stop_reason"] is None)
    elif args.case == "big":
        ok = (res["effective_status"] == 0 and f"{tag} OK" in res["final_message"]
              and res["prompt_bytes"] >= args.prompt_bytes
              and res["model_value"] == alias)
    else:
        ok = (res["effective_status"] == 0 and tag in res["final_message"]
              and res["model_value"] == alias)
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    _main()
