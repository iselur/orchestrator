#!/usr/bin/env bash
# Kimi brief, slice 4 — the kimi ISOLATION GATE. Proves EMPIRICALLY, on this box, both sides
# of the kimi credential boundary before any kimi worker launch is permitted:
#   - the codex-worker UID and the hardened service CANNOT reach the operator's ~/.kimi-code
#     credential (directly or through the service envelope);
#   - the hardened service CAN execute the bind-mounted native kimi binary and CAN read and
#     write the worker's own provisioned ~codex-worker/.kimi-code state;
#   - the provisioned state carries codex-worker ownership, 700 directories, 600 files.
# ACTIVATION CONTRACT (brief, isolation gate): kimi workers may launch only after this file
# exits 0 on THIS host. Exit 77 means the gate DID NOT RUN — that is failure for activation,
# never evidence of a pass (T1/R26); it is tolerated by strict CI only because this is a
# box-precondition drill (sudo + provisioned users), same contract as tests/worker_isolation.sh.
# Anti-vacuity design mirrors worker_isolation.sh: positive controls first, explicit verdict
# markers (a probe that never reported is a FAILURE), operator resolved never hardcoded.
set -uo pipefail
cd "$(dirname "$0")/.."

WORKER=codex-worker
WORKER_HOME=/home/$WORKER
if ! id "$WORKER" >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
  echo "SKIP kimi_worker_isolation.sh: codex-worker user or passwordless sudo absent (box-only; run scripts/setup-worker-user.sh)"
  exit 77   # did NOT run — never a pass; kimi activation stays prohibited
fi

OPERATOR="${ORCH_OPERATOR_USER:-$(id -un)}"
if [ "$OPERATOR" = root ]; then
  echo "SKIP kimi_worker_isolation.sh: operator resolved to root; run as the operator or set ORCH_OPERATOR_USER"
  exit 77
fi
OPERATOR_HOME="$(getent passwd "$OPERATOR" | cut -d: -f6)"
if [ -z "$OPERATOR_HOME" ] || [ ! -d "$OPERATOR_HOME" ]; then
  echo "SKIP kimi_worker_isolation.sh: cannot resolve home for operator '$OPERATOR' from passwd"
  exit 77
fi
echo "operator: $OPERATOR ($OPERATOR_HOME)"

OP_CRED="$OPERATOR_HOME/.kimi-code/credentials/kimi-code.json"
if [ ! -f "$OP_CRED" ]; then
  echo "SKIP kimi_worker_isolation.sh: operator has no kimi credential ($OP_CRED); kimi is not installed on this box"
  exit 77
fi
# The dispatcher's own candidate order (worker_kimi_runtime): the operator install, then PATH.
KIMI_BIN=""
for c in "$OPERATOR_HOME/.kimi-code/bin/kimi" "$OPERATOR_HOME/.local/bin/kimi" \
         /usr/local/bin/kimi /usr/bin/kimi "$(command -v kimi 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { KIMI_BIN="$(realpath -e "$c")"; break; }
done
if [ -z "$KIMI_BIN" ]; then
  echo "SKIP kimi_worker_isolation.sh: no executable kimi binary found; kimi is not installed on this box"
  exit 77
fi
if ! sudo test -f "$WORKER_HOME/.kimi-code/credentials/kimi-code.json"; then
  echo "SKIP kimi_worker_isolation.sh: worker kimi state not provisioned; run scripts/setup-worker-user.sh (77 = kimi activation stays prohibited)"
  exit 77
fi

fails=0
ok(){ echo "ok   $*"; }
bad(){ echo "FAIL $*"; fails=$((fails+1)); }
deny(){ local desc="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq 0 ]; then bad "$desc (SUCCEEDED — isolation broken)"
  elif [ "$rc" -eq 226 ]; then bad "$desc — probe never ran (exit 226); vacuous, not a denial"
  else ok "$desc — denied"; fi; }
verdict(){ local marker="$1" desc="$2" want="$3" got
  got="$(cat "$marker" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then ok "$desc"
  elif [ -z "$got" ]; then bad "$desc — probe never reported (vacuous; unit likely failed to start)"
  else bad "$desc — probe reported '$got' (isolation broken)"; fi; }

echo "== K0 harness: positive control — sudo executes commands as $WORKER"
if sudo -n -u "$WORKER" cat /etc/hostname >/dev/null 2>&1; then
  ok "sudo -u $WORKER runs commands (denials below are meaningful)"
else
  echo "FAIL positive control: cannot run commands as $WORKER — every denial would be vacuous"
  exit 1
fi

echo "== K1: codex-worker is denied the operator's kimi credential (DAC)"
deny "read $OP_CRED" sudo -u "$WORKER" cat "$OP_CRED"
deny "traverse $OPERATOR_HOME/.kimi-code" sudo -u "$WORKER" ls "$OPERATOR_HOME/.kimi-code"

echo "== K2: the worker's provisioned kimi state carries the required ownership and modes"
own_ok=1
while IFS= read -r line; do
  case "$line" in
    "$WORKER $WORKER 700 d"*|"$WORKER $WORKER 600 f"*) ;;
    *) bad "wrong ownership/mode in worker kimi state: $line"; own_ok=0 ;;
  esac
done < <(sudo find "$WORKER_HOME/.kimi-code" \( -type d -o -type f \) \
           -printf '%u %g %m %y %p\n' 2>/dev/null)
[ "$own_ok" = 1 ] && ok "every dir is 700 and every file is 600, owned $WORKER:$WORKER"

WT=/srv/codexwork/worktrees/_kimidrill
sudo rm -rf "$WT"
if ! mkdir -p "$WT" || ! setfacl -m u:"$WORKER":rwx "$WT"; then
  echo "FAIL cannot prepare drill worktree $WT (run scripts/setup-worker-user.sh)"; exit 1
fi
svc(){ sudo -n systemd-run --uid="$WORKER" --gid="$WORKER" --pipe --wait --quiet --collect \
        --unit="kimidrill-$1" --property=ProtectSystem=strict \
        --property=InaccessiblePaths="$OPERATOR_HOME" \
        --property=PrivateTmp=yes --property=NoNewPrivileges=yes \
        --setenv=HOME="$WORKER_HOME" "${@:2}"; }

echo "== K3 harness: positive control — hardened service CAN write its own worktree"
if err="$(svc w0 --property=ReadWritePaths="$WT" bash -c "echo ok > $WT/in.txt" 2>&1)" && [ -f "$WT/in.txt" ]; then
  ok "write inside worktree — allowed (positive control)"
else
  bad "positive control: cannot write its own worktree — probe services do not run"
  echo "     probe stderr: ${err:-(empty)}"
  sudo rm -rf "$WT"
  echo; echo "FAIL: kimi worker isolation drills (harness broken; $fails failed)"; exit 1
fi

echo "== K3: hardened service reads AND writes the worker's own kimi state (the dispatcher's rw path)"
svc k3 --property=ReadWritePaths="$WT" --property=ReadWritePaths="$WORKER_HOME/.kimi-code" bash -c \
  "if cat '$WORKER_HOME/.kimi-code/credentials/kimi-code.json' >/dev/null 2>&1 \
      && touch '$WORKER_HOME/.kimi-code/.drill-write' 2>/dev/null; then echo READY; else echo BROKEN; fi > '$WT/m-state'" >/dev/null 2>&1
verdict "$WT/m-state" "worker kimi state readable and writable inside the service" READY
sudo rm -f "$WORKER_HOME/.kimi-code/.drill-write"

echo "== K4: hardened service cannot reach the operator's kimi credential"
svc k4 --property=ReadWritePaths="$WT" bash -c \
  "if cat '$OP_CRED' >/dev/null 2>&1; then echo LEAK; else echo DENIED; fi > '$WT/m-opcred'" >/dev/null 2>&1
verdict "$WT/m-opcred" "service read of operator kimi credential — denied" DENIED

echo "== K5: hardened service EXECUTES the bind-mounted native kimi binary (launch-shape probe)"
# The dispatcher's exact runtime shape (worker_kimi_runtime): the resolved real binary is
# bind-mounted read-only to /opt/kimi/kimi and argv execs the destination. --version needs no
# credential or network; a version string proves the ELF runs under the real hardening.
svc k5 --property=ReadWritePaths="$WT" \
  --property=BindReadOnlyPaths="$KIMI_BIN:/opt/kimi/kimi" bash -c \
  "if /opt/kimi/kimi --version >'$WT/m-version' 2>&1; then echo READY; else echo BROKEN; fi > '$WT/m-exec'" >/dev/null 2>&1
verdict "$WT/m-exec" "bound kimi binary executes under service hardening" READY
if grep -qi kimi "$WT/m-version" 2>/dev/null; then
  ok "kimi --version reports a version string ($(tr -d '\n' < "$WT/m-version" | head -c 60))"
else
  bad "kimi --version produced no recognizable output (vacuous exec proof)"
fi
sudo rm -rf "$WT"

echo
if [ "$fails" = 0 ]; then echo "PASS: kimi worker isolation drills (0 failed)"; exit 0
else echo "FAIL: kimi worker isolation drills ($fails failed)"; exit 1; fi
