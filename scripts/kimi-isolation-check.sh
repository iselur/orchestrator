#!/usr/bin/env bash
# Kimi brief, slice 4 — the kimi ACTIVATION GATE (owner/operator, run on the target host).
# Proves EMPIRICALLY, on this box, both sides of the kimi credential boundary. Per the brief's
# Isolation gate this is an OWNER/OPERATOR host action (run it after scripts/setup-worker-user.sh),
# NOT a dispatcher per-launch box-precondition: an unconditional box-precondition returning 77
# would abort EVERY vendor's launch (dispatch.py requires PASS from all box tests), so this
# lives in scripts/ and is invoked by hand, not by scripts/test — round-1 review, high 2.
#
# CONTRACT: kimi workers may be activated only after this exits 0 on THIS host. Any non-zero
# exit — including the 77 "did not run" ladder below — means kimi activation STAYS PROHIBITED
# (a skip is never evidence of a pass; T1/R26). Drills:
#   K1  codex-worker (DAC) cannot read the operator's kimi credential or list ~/.kimi-code.
#   K2  the provisioned ~codex-worker/.kimi-code is EXACTLY {700 dir, 700 credentials dir,
#       600 config.toml, 600 credentials/kimi-code.json}, all codex-worker-owned — no extra,
#       missing, or non-regular (symlink/FIFO/socket) entries.
#   K3  the hardened service reads AND writes the worker's own kimi state (the dispatcher rw path).
#   K4  the hardened service cannot reach the operator's kimi credential.
#   K5  the DISPATCHER-VETTED native binary (resolved via worker_kimi_runtime — same ELF/trust
#       checks the launch path uses) executes --version, bound to /opt/kimi/kimi under the
#       service hardening. Unvetted output is never echoed.
# Anti-vacuity: worker-UID quiescence is required first (no concurrent worker to forge a
# verdict); every verdict is the probe's EXACT exit status reported owner-side by systemd/sudo
# (never a worker-writable file or pipe); positive controls run first; operator resolved not
# hardcoded.
set -uo pipefail
cd "$(dirname "$0")/.."

WORKER=codex-worker
WORKER_HOME=/home/$WORKER
PROHIBIT="kimi activation stays PROHIBITED"

if ! id "$WORKER" >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
  echo "SKIP: codex-worker user or passwordless sudo absent (run scripts/setup-worker-user.sh); $PROHIBIT"
  exit 77
fi

OPERATOR="${ORCH_OPERATOR_USER:-$(id -un)}"
if [ "$OPERATOR" = root ]; then
  echo "SKIP: operator resolved to root; run as the operator or set ORCH_OPERATOR_USER; $PROHIBIT"
  exit 77
fi
OPERATOR_HOME="$(getent passwd "$OPERATOR" | cut -d: -f6)"
if [ -z "$OPERATOR_HOME" ] || [ ! -d "$OPERATOR_HOME" ]; then
  echo "SKIP: cannot resolve home for operator '$OPERATOR' from passwd; $PROHIBIT"
  exit 77
fi
echo "operator: $OPERATOR ($OPERATOR_HOME)"

OP_CRED="$OPERATOR_HOME/.kimi-code/credentials/kimi-code.json"
if [ ! -f "$OP_CRED" ]; then
  echo "SKIP: operator has no kimi credential ($OP_CRED); kimi is not installed on this box; $PROHIBIT"
  exit 77
fi
if ! sudo test -f "$WORKER_HOME/.kimi-code/credentials/kimi-code.json"; then
  echo "SKIP: worker kimi state not provisioned; run scripts/setup-worker-user.sh; $PROHIBIT"
  exit 77
fi

# The dispatcher's OWN resolver picks and vets the native binary (ELF magic, owner/mode,
# ancestry, ACLs) exactly as the launch path does — this gate must prove THAT binary runs, not
# an ad-hoc `-x` guess (round-1 review, medium 4). Absent trusted runtime -> cannot vet -> skip.
TRUNTIME=/opt/orchestrator-test-runtime
if [ "$(sudo stat -c '%U:%G' "$TRUNTIME" 2>/dev/null)" != root:root ]; then
  echo "SKIP: trusted python runtime $TRUNTIME absent/not root-owned (run scripts/setup-worker-user.sh); $PROHIBIT"
  exit 77
fi
KIMI_BIN="$(ORCH_OPERATOR_USER="$OPERATOR" "$TRUNTIME/bin/python" - <<'PY'
import importlib.util
s = importlib.util.spec_from_file_location("d", "scripts/dispatch.py")
d = importlib.util.module_from_spec(s); s.loader.exec_module(d)
# The kimi runtime resolver ships in slice 3 (dispatcher wiring, PR #165). If the INSTALLED
# dispatcher predates it, kimi cannot be launched at all yet — print the sentinel so the gate
# refuses with a clear "install slice 3 first", never a silent empty resolve (round-2 review).
fn = getattr(d, "worker_kimi_runtime", None)
if fn is None:
    print("__NO_RESOLVER__")
else:
    rt = fn()                         # (argv, [(real_src, /opt/kimi/kimi)], entry) or None
    print(rt[1][0][0] if rt else "")
PY
)"
if [ "$KIMI_BIN" = "__NO_RESOLVER__" ]; then
  echo "SKIP: the installed dispatcher has no kimi runtime resolver yet — install slice 3 (PR #165) first; $PROHIBIT"
  exit 77
fi
if [ -z "$KIMI_BIN" ] || ! sudo test -f "$KIMI_BIN"; then
  echo "SKIP: no dispatcher-vetted native kimi runtime on this box (worker_kimi_runtime found none); $PROHIBIT"
  exit 77
fi
echo "dispatcher-vetted kimi binary: $KIMI_BIN"

# Round-3/4 review (high): grading a probe's STDOUT (or a marker file) is forgeable by a
# concurrent same-UID codex-worker (write /proc/<pid>/fd/1 or signal the probe). Two defenses:
#   (a) QUIESCENCE — refuse unless the worker UID is idle, so no concurrent worker exists to
#       inject or signal. Checked as ROOT (round-4: an operator-run pgrep can miss another UID's
#       processes under /proc hidepid). This is an owner-operated activation gate: the owner
#       stops dispatch first, so the check-to-drill TOCTOU is closed by procedure, not by luck.
#   (b) Verdicts come from the EXACT process exit status (svc: systemd/PID1; direct: bash $?).
#       A signalled child reports 128+sig, and the deny classifier below treats ONLY a clean
#       normal-exit denial as a denial — a signalled or abnormal probe FAILS CLOSED. Forging a
#       specific exit needs ptrace, which quiescence (no attacker present) closes. (NoNewPrivileges
#       is NOT a ptrace defense — it only blocks privilege gain through execve.)
if sudo -n pgrep -u "$WORKER" >/dev/null 2>&1; then
  echo "SKIP: $WORKER has running processes — run this gate with the worker UID quiescent (stop dispatch first); $PROHIBIT"
  exit 77
fi

fails=0
ok(){ echo "ok   $*"; }
bad(){ echo "FAIL $*"; fails=$((fails+1)); }
# Round-4 review (high): `cmd && exit 9 || exit 0` mapped EVERY nonzero — including a signalled
# child (128+sig) — to "denied", so a same-UID signal forged a false denial. Instead run the
# command, capture its OWN exit, and classify inside the probe: leak (rc 0) -> 9, signalled or
# abnormal (rc>=128) -> 8, a clean access failure (rc 1..127) -> 0. The classifier then accepts
# ONLY 0 as a denial; 9 is a leak; anything else (incl. an outer-shell signal, which systemd/bash
# report as >=128) is vacuous and fails closed. DENY_WRAP is appended after the probed command.
DENY_WRAP='rc=$?; if [ $rc -eq 0 ]; then exit 9; elif [ $rc -ge 128 ]; then exit 8; else exit 0; fi'
classify_deny(){ local desc="$1" rc="$2"
  case "$rc" in
    0) ok "$desc — denied";;
    9) bad "$desc (SUCCEEDED — isolation broken)";;
    *) bad "$desc — probe abnormal/signalled (exit $rc); vacuous, not a denial";;
  esac; }

echo "== K0 harness: positive control — worker commands run AND the exit channel distinguishes codes"
# Prove BOTH that units run and that a NON-zero code is faithfully distinguished (round-4: a
# harness that only checks exit 0 cannot tell a real denial from a lost channel).
sudo -n -u "$WORKER" bash -c 'exit 0'; pc0=$?
sudo -n -u "$WORKER" bash -c 'exit 9'; pc9=$?
if [ "$pc0" -eq 0 ] && [ "$pc9" -eq 9 ]; then
  ok "worker exit status reaches the owner exactly (0->0, 9->9; verdicts are meaningful)"
else
  echo "FAIL positive control: worker exit channel is lossy (0->$pc0, 9->$pc9); $PROHIBIT"
  exit 1
fi

echo "== K1: codex-worker is denied the operator's kimi credential (DAC)"
sudo -n -u "$WORKER" bash -c "cat '$OP_CRED' >/dev/null 2>&1; $DENY_WRAP"; classify_deny "read $OP_CRED" $?
sudo -n -u "$WORKER" bash -c "ls '$OPERATOR_HOME/.kimi-code' >/dev/null 2>&1; $DENY_WRAP"; classify_deny "traverse $OPERATOR_HOME/.kimi-code" $?

echo "== K2: the worker's provisioned kimi state is EXACTLY the required tree (no extra/foreign entries)"
# %y is the type: d/f/l/... — anything but the four expected regular entries fails, INCLUDING a
# symlink (which the credential precheck's `test -f` would have followed — round-1 review, high 3).
# `find` errors (permission/vanished) print to stderr and are turned into an explicit failure;
# zero output is NOT silently treated as success.
k2_err="$(mktemp)"
mapfile -t ST < <(sudo find "$WORKER_HOME/.kimi-code" -mindepth 0 \
                    -printf '%y %m %u:%g %P\n' 2>"$k2_err"; echo "rc=$?")
find_rc="${ST[-1]#rc=}"; unset 'ST[-1]'
if [ "$find_rc" != 0 ] || [ -s "$k2_err" ]; then
  bad "find over the worker kimi state errored (rc=$find_rc): $(cat "$k2_err" 2>/dev/null)"
fi
rm -f "$k2_err"
# Exact membership: the root dir (empty %P), config.toml, credentials dir, and the credential.
want="$(printf '%s\n' \
  "d 700 :$WORKER:$WORKER" \
  "f 600 config.toml:$WORKER:$WORKER" \
  "d 700 credentials:$WORKER:$WORKER" \
  "f 600 credentials/kimi-code.json:$WORKER:$WORKER" | sort)"
have="$(printf '%s\n' "${ST[@]}" | awk '{print $1" "$2" "$4":"$3}' | sort)"
if [ "$have" = "$want" ]; then
  ok "worker kimi state is exactly {700 ., 600 config.toml, 700 credentials, 600 credential}, owned $WORKER"
else
  bad "worker kimi state does not match the required tree"
  echo "--- expected"; printf '%s\n' "$want"
  echo "--- observed"; printf '%s\n' "$have"
fi

# svc runs a probe as a hardened transient unit and returns the unit's EXACT exit status
# (systemd/PID1 → systemd-run --wait → this shell), the owner-controlled verdict channel.
svc(){ sudo -n systemd-run --uid="$WORKER" --gid="$WORKER" --wait --quiet --collect \
        --unit="kimicheck-$1" --property=ProtectSystem=strict \
        --property=InaccessiblePaths="$OPERATOR_HOME" \
        --property=PrivateTmp=yes --property=NoNewPrivileges=yes \
        --setenv=HOME="$WORKER_HOME" "${@:2}" >/dev/null 2>&1; }
# Grade a probe unit on its exact expected exit code; any other (incl. signalled 128+sig, or
# 226 = unit failed to start) fails closed.
expect(){ local unit="$1" want="$2" desc="$3"; shift 3
  svc "$unit" "$@"; local rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$desc"; else bad "$desc (exit $rc, wanted $want)"; fi; }

echo "== K3 harness: positive control — a hardened probe unit runs AND distinguishes exit codes"
# Round-4 review (medium): exercise both a 0 and a non-0 code so a later nonzero verdict is
# proven meaningful (systemd propagates ordinary exit codes exactly and maps signals distinctly).
svc w0 bash -c 'exit 0'; sc0=$?
svc w9 bash -c 'exit 9'; sc9=$?
if [ "$sc0" -eq 0 ] && [ "$sc9" -eq 9 ]; then
  ok "hardened probe unit runs and propagates exit status exactly (0->0, 9->9)"
else
  bad "positive control: service exit channel is lossy (0->$sc0, 9->$sc9) — service verdicts would be vacuous"
  echo; echo "FAIL: kimi isolation drills (harness broken; $fails failed); $PROHIBIT"; exit 1
fi

echo "== K3: hardened service reads AND writes the worker's own kimi state (the dispatcher rw path)"
# exit 0 iff BOTH the read and the write succeed; the write target is removed afterward.
expect k3 0 "worker kimi state readable and writable inside the service" \
  --property=ReadWritePaths="$WORKER_HOME/.kimi-code" bash -c \
  "cat '$WORKER_HOME/.kimi-code/credentials/kimi-code.json' >/dev/null 2>&1 \
     && touch '$WORKER_HOME/.kimi-code/.drill-write'"
sudo rm -f "$WORKER_HOME/.kimi-code/.drill-write"

echo "== K4: hardened service cannot reach the operator's kimi credential"
# Same signal-safe classification as K1 (round-4): leak->9, signalled/abnormal->8, clean
# denial->0; only a clean 0 is accepted as a denial.
svc k4 bash -c "cat '$OP_CRED' >/dev/null 2>&1; $DENY_WRAP"
classify_deny "service read of operator kimi credential" $?

echo "== K5: the DISPATCHER-VETTED native kimi binary executes under service hardening"
# The resolved real binary bind-mounted RO to /opt/kimi/kimi, argv execs the destination —
# exactly the slice-3 launch shape. --version needs no credential or network. The binary's own
# output is discarded (not guaranteed credential-free); only its exit status is graded.
expect k5 0 "bound dispatcher-vetted kimi binary executes under service hardening" \
  --property=PrivateNetwork=yes --property=BindReadOnlyPaths="$KIMI_BIN:/opt/kimi/kimi" \
  bash -c "/opt/kimi/kimi --version >/dev/null 2>&1"

echo
if [ "$fails" = 0 ]; then echo "PASS: kimi isolation drills (0 failed) — kimi activation permitted on this host"; exit 0
else echo "FAIL: kimi isolation drills ($fails failed); $PROHIBIT"; exit 1; fi
