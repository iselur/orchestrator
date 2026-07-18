#!/usr/bin/env bash
# kimi_acp.drive() fail-closed contract (PLAN-009 slice 1) against a deterministic fake
# stdio peer. Pure logic — no sudo, no network, no kimi install. The load-bearing case is
# the C1 regression: a peer that exits 0 WITHOUT a terminal end_turn response must yield a
# nonzero EFFECTIVE status (amendment 2026-07-18) — plus raw-before-parse frame recording,
# model read-back enforcement, agent-request refusal, duplicate/unknown response ids, wrong
# stop reason, JSON-RPC errors, deadline expiry, and a >MAX_ARG_STRLEN (131072) prompt
# completing through real pipes without a write-side deadlock (N4; hardened-chain variant
# is proven live by scripts/kimi-acp-check.sh). Review acp-slice-1 round 1 and 2
# falsifiers are pinned here: an end_turn reply to a never-read prompt, malformed-shape
# frames (non-string method, string params on any notification, non-object config option
# even for a foreign session, missing jsonrpc member), a stale other-session model
# read-back, and a same-session read-back held inside sink I/O across the set_model
# watermark must each fail closed. Round 3: field-level type violations (numeric
# sessionId / sessionUpdate / content type, boolean response id) fail closed even when
# the session otherwise completes; the confirm fence is the set_model RESPONSE seq, so an
# update received while the set_model write is still pending cannot confirm while the real
# CLI's order (read-back before the response, re-emitted after set_mode) still grades 0;
# a prompt-stage error keeps the echoed model_value so the operator negative control can
# tell it from a set_model rejection.
set -uo pipefail
cd "$(dirname "$0")/.."
PY="${ORCH_TEST_PY:-.venv/bin/python}"
[ -x "$PY" ] || { echo "SKIP kimi_acp_driver.sh: trusted Python runtime absent"; exit 77; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/peer.py" <<'PEER'
import json, os, sys, time

MODE = os.environ["PEER_MODE"]
ALIAS = "kimi-code/k3"

def send(o):
    sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()

def recv():
    line = sys.stdin.readline()
    if not line:
        sys.exit(0)
    return json.loads(line)

def note_model(value, sid="s1"):
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid,
          "update": {"sessionUpdate": "config_option_update",
                     "configOptions": [{"id": "model", "currentValue": value}]}}})

def chunk(text):
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1",
          "update": {"sessionUpdate": "agent_message_chunk",
                     "content": {"type": "text", "text": text}}}})

def drain():
    while sys.stdin.readline():
        pass
    sys.exit(0)

m = recv()  # initialize
if MODE == "stalemodel":
    note_model(ALIAS, sid="stale-old")  # review r1 falsifier: pre-session, other session
if MODE == "nojsonrpc":
    send({"id": m["id"], "result": {"protocolVersion": 1, "agentCapabilities": {}}})
    drain()
send({"jsonrpc": "2.0", "id": True if MODE == "boolid" else m["id"],
      "result": {"protocolVersion": 99 if MODE == "badversion" else 1,
                 "agentCapabilities": {}}})
if MODE == "badversion":
    drain()
if MODE == "malformed":
    sys.stdout.write("this is not json\n"); sys.stdout.flush()
    drain()

m = recv()  # session/new
if MODE == "agentreq":
    send({"jsonrpc": "2.0", "id": 777, "method": "fs/read_text_file",
          "params": {"path": "/etc/passwd"}})
    drain()
send({"jsonrpc": "2.0", "id": m["id"], "result": {"sessionId": "s1"}})
note_model("kimi-code/kimi-for-coding")  # the real CLI's default: NOT the frozen alias
if MODE == "strparams":
    send({"jsonrpc": "2.0", "method": "session/update", "params": "bogus"})
    drain()
# review r2 falsifiers: inject one malformed frame, then keep serving the session
# normally — without the fix the session completes and grades 0
if MODE == "nummethod":
    send({"jsonrpc": "2.0", "method": 7})
if MODE == "unkstrparams":
    send({"jsonrpc": "2.0", "method": "weird/notification", "params": "bogus"})
if MODE == "foreignbadopt":
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "other",
          "update": {"sessionUpdate": "config_option_update",
                     "configOptions": ["not-an-object"]}}})
# review r3 falsifiers: field-level type violations, same inject-then-continue pattern
if MODE == "numsid":
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": 7,
          "update": {"sessionUpdate": "agent_message_chunk",
                     "content": {"type": "text", "text": "x"}}}})
if MODE == "numkind":
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1",
          "update": {"sessionUpdate": 7}}})
if MODE == "numctype":
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1",
          "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": 7}}}})
if MODE == "badopts":
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1",
          "update": {"sessionUpdate": "config_option_update",
                     "configOptions": ["not-an-object"]}}})
    drain()

m = recv()  # session/set_model
if MODE == "modelerr":
    send({"jsonrpc": "2.0", "id": m["id"],
          "error": {"code": -32603, "message": "model not configured"}})
    drain()
if MODE == "cliorder":
    note_model(ALIAS)  # real CLI order: read-back BEFORE the set_model response...
send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
if MODE == "negecho":
    note_model(m["params"]["modelId"])  # confirm whatever was asked, even a bogus alias
elif MODE not in ("noconfirm", "stalemodel", "cliorder"):
    note_model(ALIAS)

m = recv()  # session/set_mode
send({"jsonrpc": "2.0", "id": m["id"], "result": {}})
if MODE == "cliorder":
    note_model(ALIAS)  # ...re-emitted after set_mode: the qualifying read-back
if MODE in ("noread", "noreadhang"):
    # answer the prompt request (next id) WITHOUT ever reading it — review r1 falsifier
    send({"jsonrpc": "2.0", "id": m["id"] + 1, "result": {"stopReason": "end_turn"}})
    if MODE == "noread":
        sys.exit(0)
    time.sleep(60)

m = recv()  # session/prompt
ptext = m["params"]["prompt"][0]["text"]
if MODE == "exit0noterm":
    chunk("partial answer")
    sys.exit(0)  # clean exit, no terminal response — the C1 case
if MODE == "eofmid":
    chunk("half")
    sys.exit(1)
if MODE in ("prompterr", "negecho"):
    send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32000, "message": "boom"}})
elif MODE == "badstop":
    chunk("truncated")
    send({"jsonrpc": "2.0", "id": m["id"], "result": {"stopReason": "max_tokens"}})
elif MODE == "dupid":
    send({"jsonrpc": "2.0", "id": 1, "result": {}})  # stale duplicate of an answered id
elif MODE == "slow":
    time.sleep(60)
elif MODE == "bigecho":
    chunk("LEN=%d" % len(ptext.encode()))
    send({"jsonrpc": "2.0", "id": m["id"], "result": {"stopReason": "end_turn"}})
else:  # ok
    chunk("hello ")
    chunk("world")
    send({"jsonrpc": "2.0", "id": m["id"], "result": {"stopReason": "end_turn"}})
drain()
PEER

if TMP="$TMP" "$PY" - <<'PY'
import importlib.util, json, os, subprocess, sys, threading, time

spec = importlib.util.spec_from_file_location("kimi_acp", "scripts/kimi_acp.py")
ka = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ka)

TMP = os.environ["TMP"]
PEER = os.path.join(TMP, "peer.py")
ALIAS = "kimi-code/k3"
fails = []

def run(mode, prompt="ping", alias=ALIAS, deadline=15):
    sink_path = os.path.join(TMP, mode + ".events.jsonl")
    with open(sink_path, "wb") as sink:
        proc = subprocess.Popen([sys.executable, PEER], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                env={**os.environ, "PEER_MODE": mode})
        res = ka.drive(proc, prompt_text=prompt, cwd="/tmp", model_alias=alias,
                       frame_sink=sink, deadline_s=deadline)
    res["events"] = open(sink_path, "rb").read()
    return res

def case(name, cond, res):
    if cond:
        print(f"  ok: {name}")
    else:
        fails.append(name)
        print(f"  FAIL: {name}: {({k: v for k, v in res.items() if k != 'events'})}")

r = run("ok")
case("happy path grades 0", r["effective_status"] == 0 and r["failure"] is None
     and r["stop_reason"] == "end_turn" and r["proc_exit"] == 0, r)
case("happy path recovers chunk text", r["final_message"] == "hello world", r)
case("happy path confirms model read-back", r["model_value"] == ALIAS, r)
first = json.loads(r["events"].splitlines()[0])
case("raw frames recorded from the handshake on", first.get("id") == 1
     and first["result"]["protocolVersion"] == 1, r)

r = run("exit0noterm")
case("C1: clean exit 0 without end_turn is NOT success",
     r["proc_exit"] == 0 and r["effective_status"] != 0 and r["failure"] == "eof", r)

r = run("malformed")
case("malformed frame fails closed", r["effective_status"] != 0
     and r["failure"] == "malformed_frame", r)
case("malformed frame still raw-recorded before parse",
     b"this is not json" in r["events"], r)

r = run("prompterr")
case("JSON-RPC error on prompt fails closed", r["effective_status"] != 0
     and r["failure"] == "jsonrpc_error", r)

r = run("modelerr")
case("JSON-RPC error on set_model fails closed", r["effective_status"] != 0
     and r["failure"] == "jsonrpc_error", r)

r = run("noconfirm", deadline=3)
case("missing model read-back fails closed", r["effective_status"] != 0
     and r["failure"] == "model_unconfirmed", r)

r = run("badversion")
case("protocol version mismatch fails closed", r["effective_status"] != 0
     and r["failure"] == "protocol_version", r)

r = run("badstop")
case("non-end_turn stop reason fails closed", r["effective_status"] != 0
     and r["failure"] == "stop_reason", r)
case("chunks before a bad stop are still recovered",
     r["final_message"] == "truncated", r)

r = run("eofmid")
case("EOF mid-stream fails closed with chunks kept", r["effective_status"] != 0
     and r["failure"] == "eof" and r["final_message"] == "half", r)

r = run("dupid")
case("duplicate/unknown response id fails closed", r["effective_status"] != 0
     and r["failure"] == "unexpected_response_id", r)

r = run("slow", deadline=3)
case("deadline expiry fails closed and reaps the peer", r["effective_status"] != 0
     and r["failure"] == "deadline" and r["proc_exit"] is not None, r)

r = run("agentreq")
case("agent-to-client request is refused and fails closed",
     r["effective_status"] != 0 and r["failure"] == "agent_request", r)

r = run("noread", prompt="y" * 200_000)
case("r1: end_turn for a never-read prompt fails closed",
     r["effective_status"] != 0 and r["failure"] == "write_failed", r)

r = run("noreadhang", prompt="y" * 200_000, deadline=3)
case("r1: unread prompt held open is a write stall",
     r["effective_status"] != 0 and r["failure"] == "write_stall", r)

r = run("nojsonrpc")
case("r1: frame missing the jsonrpc member fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("strparams")
case("r1: session/update with string params fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("badopts")
case("r1: non-object config option entry fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("stalemodel", deadline=3)
case("r1: stale other-session read-back cannot confirm set_model",
     r["effective_status"] != 0 and r["failure"] == "model_unconfirmed", r)

r = run("nummethod")
case("r2: non-string method fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("unkstrparams")
case("r2: unknown notification with string params fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("foreignbadopt")
case("r2: foreign-session non-object config option fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("numsid")
case("r3: numeric sessionId fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("numkind")
case("r3: numeric sessionUpdate discriminator fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("numctype")
case("r3: numeric content type fails closed",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("boolid")
case("r3: boolean response id is not our integer request id (True == 1)",
     r["effective_status"] != 0 and r["failure"] == "malformed_frame", r)

r = run("negecho", alias="kimi-code/bogus-echo")
case("r3: prompt-stage error keeps the echoed model_value (negative-control discriminator)",
     r["effective_status"] != 0 and r["failure"] == "jsonrpc_error"
     and r["model_value"] == "kimi-code/bogus-echo", r)

r = run("cliorder")
case("r3: real-CLI order (read-back before response, again after set_mode) grades 0",
     r["effective_status"] == 0 and r["model_value"] == ALIAS, r)

# review r2 falsifier: a same-session read-back RECEIVED before set_model but held inside
# a slow frame-sink write — so not yet queued when the watermark is taken — must not
# confirm; the receive-order seq is stamped before sink I/O, so the watermark rejects it.
class HoldSink:
    def __init__(self):
        self.in_sink = threading.Event()
        self.release = threading.Event()
    def write(self, line):
        if b"HOLDME" in line:
            self.in_sink.set()
            self.release.wait(10)
    def flush(self):
        pass

rfd, wfd = os.pipe()
class FakeProc:
    stdout = os.fdopen(rfd, "rb")
    stdin = None

sink = HoldSink()
s = ka._Session(FakeProc(), sink)
s.sid = "s1"
stale = {"jsonrpc": "2.0", "method": "session/update",
         "params": {"sessionId": "s1", "marker": "HOLDME",
                    "update": {"sessionUpdate": "config_option_update",
                               "configOptions": [{"id": "model", "currentValue": ALIAS}]}}}
os.write(wfd, (json.dumps(stale) + "\n").encode())
assert sink.in_sink.wait(10)  # the stale line is seq-stamped and held inside sink I/O
s.model_watermark = s.rx_seq  # the fence request(arm_model=True) takes at the response
s.model_value = None
sink.release.set()
msg = s._recv(time.monotonic() + 10, "model_unconfirmed")
case("r2: sink-held pre-transaction same-session read-back cannot confirm",
     msg.get("method") == "session/update" and s.model_value is None,
     {"model_value": s.model_value, "cur_seq": s.cur_seq,
      "watermark": s.model_watermark})
os.write(wfd, (json.dumps(stale).replace("HOLDME", "FRESH") + "\n").encode())
s._recv(time.monotonic() + 10, "model_unconfirmed")
case("r2: post-watermark same-session read-back does confirm",
     s.model_value == ALIAS, {"model_value": s.model_value})
os.close(wfd)

# review r3 falsifier: a same-session read-back received while the set_model write is
# still pending must not confirm — the fence is the set_model RESPONSE frame's seq, and
# the pending-window update is necessarily received (and stamped) before that response.
class BlockingStdin:
    def __init__(self):
        self.release = threading.Event()
        self.wrote = threading.Event()
    def write(self, data):
        self.release.wait(10)
        self.wrote.set()
        return len(data)
    def flush(self):
        pass

rfd2, wfd2 = os.pipe()
class FakeProc2:
    stdout = os.fdopen(rfd2, "rb")
    stdin = BlockingStdin()

class PlainSink:
    def __init__(self):
        self.seen = threading.Event()
    def write(self, line):
        self.seen.set()
    def flush(self):
        pass

sink2 = PlainSink()
s2 = ka._Session(FakeProc2(), sink2)
s2.sid = "s1"
got = {}
def do_set_model():
    got["res"] = s2.request("session/set_model",
                            {"sessionId": "s1", "modelId": ALIAS},
                            time.monotonic() + 10, arm_model=True)
t = threading.Thread(target=do_set_model, daemon=True)
t.start()
pend = {"jsonrpc": "2.0", "method": "session/update",
        "params": {"sessionId": "s1",
                   "update": {"sessionUpdate": "config_option_update",
                              "configOptions": [{"id": "model", "currentValue": ALIAS}]}}}
os.write(wfd2, (json.dumps(pend) + "\n").encode())
assert sink2.seen.wait(10)  # the update is seq-stamped and queued before the write ends
FakeProc2.stdin.release.set()
assert FakeProc2.stdin.wrote.wait(10)
os.write(wfd2, b'{"jsonrpc": "2.0", "id": 1, "result": {}}\n')  # no read-back after
t.join(10)
case("r3: update received during a pending set_model write cannot confirm",
     not t.is_alive() and got.get("res") == {} and s2.model_value is None,
     {"model_value": s2.model_value, "watermark": s2.model_watermark,
      "rx_seq": s2.rx_seq})
os.write(wfd2, (json.dumps(pend) + "\n").encode())
s2._recv(time.monotonic() + 10, "model_unconfirmed")
case("r3: post-response same-session read-back does confirm",
     s2.model_value == ALIAS, {"model_value": s2.model_value})
os.close(wfd2)

big = "x" * 140_000  # > MAX_ARG_STRLEN 131072
r = run("bigecho", prompt=big)
case("oversized prompt completes with no write deadlock",
     r["effective_status"] == 0 and f"LEN={len(big.encode())}" in r["final_message"], r)

sys.exit(1 if fails else 0)
PY
then echo "PASS kimi_acp_driver.sh"; exit 0
else echo "FAIL kimi_acp_driver.sh"; exit 1; fi
