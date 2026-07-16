#!/usr/bin/env bash
# R77 / PLAN-007 earliest falsifiable proof — round-3 revision of the DISPOSABLE lifecycle
# falsifier. Drives tests/lifecycle/proto.sh plus a long-lived interactive surrogate on a
# PRIVATE tmux socket. Nothing touches production paths, credentials, sessions, or `claude -p`.
# Round-3 deltas: ready-acknowledged race barrier; point-SPECIFIC crash oracles incl. the
# interrupted-consumption acquire fence; HALT proven at the COMMIT INSTANT via the LF_HALT_AT
# staging hook; dead-letters fence observations, kills, and re-flags; observation order is
# server-assigned (caller tick labels are data); consume path validates the handoff fully and
# honors N=1; teardown and the repo-write audit complete BEFORE the result manifest is built,
# so the manifest binds artifact digests, per-scenario results, teardown outcome, and the final
# exit status. Loud-SKIP (77) box contract when tmux is absent — a skip is never a pass.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v tmux  >/dev/null 2>&1 || { echo "SKIP lifecycle_falsifier.sh: tmux absent (box-only falsifier)"; exit 77; }
command -v flock >/dev/null 2>&1 || { echo "SKIP lifecycle_falsifier.sh: flock absent"; exit 77; }

START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fails=0
RESULTS=()
check() { # $1 name, $2 rc (0 ok)
    if [ "$2" -eq 0 ]; then echo "ok   $1"; RESULTS+=("ok   $1"); else echo "FAIL $1"; RESULTS+=("FAIL $1"); fails=1; fi
}

ROOT=$(mktemp -d)
SOCK="lf-$$"
TMUX_SESSION="lf-falsifier-$$-$RANDOM"
STAMP="$ROOT/repo-stamp"; touch "$STAMP"; sleep 0.05
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/fake-home/.claude"
echo 'fake-credential-material' > "$ROOT/fake-home/.claude/.credentials.json"

. tests/lifecycle/proto.sh
lf_init "$ROOT/state" supervisor-token

# ---- interactive surrogate (long-lived, private tmux server; NEVER claude -p) -------------------
cat > "$ROOT/surrogate.sh" <<'SURR'
#!/usr/bin/env bash
set -u
FIFO="$1"; OUT="$2"
while IFS= read -r cmd < "$FIFO"; do
    case "$cmd" in
        work)  ( sleep 0.2; echo "child-work-done" >> "$OUT" ) & wait ;;
        ping)  echo pong >> "$OUT" ;;
        stop)  echo stopped >> "$OUT"; exit 0 ;;
    esac
done
SURR
chmod +x "$ROOT/surrogate.sh"
mkfifo "$ROOT/cmds"
tmux -L "$SOCK" new-session -d -s "$TMUX_SESSION" "HOME='$ROOT/fake-home' '$ROOT/surrogate.sh' '$ROOT/cmds' '$ROOT/events'"
sleep 0.3
tmux -L "$SOCK" has-session -t "$TMUX_SESSION" 2>/dev/null
check "surrogate runs long-lived on a PRIVATE tmux socket (own server)" $?
tmux has-session -t "$TMUX_SESSION" 2>/dev/null; [ $? -ne 0 ]
check "the surrogate session is absent from the default tmux server" $?
echo work > "$ROOT/cmds"; sleep 0.6
grep -q child-work-done "$ROOT/events" 2>/dev/null
check "surrogate spawns and completes controlled child work (no claude -p anywhere)" $?

# ---- id sanitization ------------------------------------------------------------------------------
lf_acquire "../evil" sessA 60 >/dev/null 2>&1; [ $? -eq 1 ];   check "row id '../evil' refuses (no LF_ROOT escape)" $?
lf_acquire ROWX "../evil" 60 >/dev/null 2>&1; [ $? -eq 1 ];    check "session id '../evil' refuses" $?
g0=$(lf_acquire ROWX sessA 60)
lf_start_job ROWX sessA "$g0" "../../evil" 2>/dev/null; [ $? -eq 1 ]; check "job id '../../evil' refuses" $?
lf_recover "../evil" >/dev/null 2>&1; [ $? -eq 1 ];            check "the read-only recovery API sanitizes its row id too" $?
lf_observe sessA "stale
class=unknown" id ROWX "$g0" t1 2>/dev/null; [ $? -eq 1 ];     check "a multiline/forged class value refuses (enum + single-token fields)" $?
[ ! -e "$ROOT/evil" ] && [ ! -e "$(dirname "$ROOT")/evil" ];   check "no escaped file was created" $?
lf_release ROWX sessA "$g0"

# ---- 1+2: race with READY ACKNOWLEDGEMENTS — both racers provably spinning before release ----------
( : > "$ROOT/readyA"; until [ -e "$ROOT/go" ]; do :; done; lf_acquire ROW1 sessA 60 > "$ROOT/raceA" 2>/dev/null ) &
( : > "$ROOT/readyB"; until [ -e "$ROOT/go" ]; do :; done; lf_acquire ROW1 sessB 60 > "$ROOT/raceB" 2>/dev/null ) &
until [ -e "$ROOT/readyA" ] && [ -e "$ROOT/readyB" ]; do :; done
: > "$ROOT/go"; wait
winners=0 own="" gen=""
[ -s "$ROOT/raceA" ] && { winners=$((winners+1)); own=sessA; gen=$(cat "$ROOT/raceA"); }
[ -s "$ROOT/raceB" ] && { winners=$((winners+1)); own=sessB; gen=$(cat "$ROOT/raceB"); }
[ "$winners" -eq 1 ] && [ "$gen" = "1" ]
check "race (both racers acknowledged ready before release): exactly one wins generation 1" $?
loser=$( [ "$own" = sessA ] && echo sessB || echo sessA )
lf_acquire ROW1 "$own" 60 >/dev/null 2>&1; [ $? -eq 1 ]
check "the LIVE owner cannot re-acquire its own row (renew is the only path)" $?
lf_start_job ROW1 "$own" "$gen" JOB1;                          check "winner starts exactly one mapped job" $?
lf_start_job ROW1 "$own" "$gen" JOB1 2>/dev/null; [ $? -eq 1 ]; check "duplicate job launch refuses (atomic create-once)" $?
lf_start_job ROW1 "$loser" "$gen" JOB2 2>/dev/null; [ $? -eq 1 ]; check "loser cannot start a job (lease CAS)" $?
grep -q "session=$own" "$ROOT/state/jobs/JOB1";                check "forward trace: job names row, generation, session" $?
[ "$(lf_jobs_of_lease ROW1 "$gen")" = "JOB1" ];                check "reverse trace: the lease lists exactly the jobs it authorized" $?

# ---- 3: soft trip ---------------------------------------------------------------------------------
lf_soft_trip ROW1 "$loser" "$gen" 2>/dev/null; [ $? -eq 1 ];   check "a non-owner cannot request rotation (CAS)" $?
lf_soft_trip ROW1 "$own" "$gen";                               check "the owner requests rotation at a soft threshold" $?
lf_renew ROW1 "$own" "$gen" 60;                                check "soft trip: current task continues (renew ok — no mid-task rotation)" $?
lf_start_job ROW1 "$own" "$gen" JOB-NEW 2>/dev/null; [ $? -eq 1 ]; check "soft trip: NEW job refused until the boundary" $?
lf_acquire ROW1 sessC 60 >/dev/null 2>&1; [ $? -eq 1 ];        check "soft trip: NEW acquisition refused (live lease + rotate marker)" $?

# ---- 4: safe boundary -------------------------------------------------------------------------------
lf_commit_boundary ROW1 "$own" "$gen";                         check "boundary: handoff committed, lease released, marker cleared — one transaction" $?
[ ! -e "$ROOT/state/rows/ROW1.rotate" ];                       check "the fulfilled rotation request is gone" $?
lf_acquire ROW1 sessE 60 >/dev/null 2>&1; [ $? -eq 1 ];        check "an unconsumed handoff fences bare acquisition" $?
grep -q '^source=ledger$' "$ROOT/state/handoffs/ROW1.gen$gen"; check "handoff declares its ledger derivation" $?
grep -q "jobs=JOB1" "$ROOT/state/handoffs/ROW1.gen$gen";       check "handoff carries the durable job map (reverse trace, not prose)" $?
echo stop > "$ROOT/cmds"; sleep 0.4
grep -q stopped "$ROOT/events";                                check "owner session self-stops at the boundary" $?

# ---- 5: successor -----------------------------------------------------------------------------------
g2=$(lf_consume_handoff ROW1 sessC);                           check "successor consumes handoff AND receives its lease in ONE transaction" $?
[ "$g2" -gt "$gen" ];                                          check "generation is monotonic across rotation" $?
lf_consume_handoff ROW1 sessD 2>/dev/null; [ $? -eq 1 ];       check "second consumption refuses" $?
lf_start_job ROW1 sessC "$g2" JOB1 2>/dev/null; [ $? -eq 1 ];  check "successor cannot duplicate the predecessor's job id" $?
g_pre=$(lf_acquire ROWP sessP 60); lf_start_job ROWP sessP "$g_pre" JOBP
lf_consume_handoff ROWP sessQ 2>/dev/null; [ $? -eq 1 ];       check "consumption refuses while the from-lease is LIVE" $?
lf_commit_boundary ROWP sessP "$g_pre"
sed -i 's/^row=.*/row=ROWZ/' "$ROOT/state/handoffs/ROWP.gen$g_pre"
lf_consume_handoff ROWP sessQ 2>/dev/null; [ $? -eq 1 ];       check "a handoff naming the WRONG row refuses (full validation)" $?
sed -i 's/^row=.*/row=ROWP/; s/^from_generation=.*/from_generation=999/' "$ROOT/state/handoffs/ROWP.gen$g_pre"
lf_consume_handoff ROWP sessQ 2>/dev/null; [ $? -eq 1 ];       check "a handoff at the WRONG generation refuses" $?
sed -i "s/^from_generation=.*/from_generation=$g_pre/" "$ROOT/state/handoffs/ROWP.gen$g_pre"
cp "$ROOT/state/handoffs/ROWP.gen$g_pre" "$ROOT/state/handoffs/ROWP.gen999"
lf_consume_handoff ROWP sessQ 2>/dev/null; [ $? -eq 1 ];       check "TWO handoffs for one row refuse (exactly-one rule)" $?
rm "$ROOT/state/handoffs/ROWP.gen999"
lf_consume_handoff ROWP sessQ >/dev/null;                      check "the repaired single valid handoff consumes cleanly" $?

# ---- 6: expiry + clock discipline ---------------------------------------------------------------------
g3=$(lf_acquire ROW2 sessOld 1); sleep 2
g4=$(lf_acquire ROW2 sessNew 60);                              check "expired lease: fresh session acquires the next generation" $?
[ "$g4" -gt "$g3" ];                                           check "takeover raises the generation" $?
stale_fails=0
for op in "lf_renew ROW2 sessOld $g3 60" "lf_release ROW2 sessOld $g3" \
          "lf_start_job ROW2 sessOld $g3 JOBX" "lf_commit_boundary ROW2 sessOld $g3" \
          "lf_soft_trip ROW2 sessOld $g3" "lf_activity ROW2 sessOld $g3" \
          "lf_safety_flag ROW2 sessOld $g3"; do
    $op >/dev/null 2>&1; [ $? -eq 1 ] || { echo "FAIL stale session not refused: $op"; stale_fails=1; }
done
check "stale session refused at every fenced operation" $stale_fails
sed -i 's/^expiry=.*/expiry=not-a-number/' "$ROOT/state/rows/ROW2.lease"
lf_acquire ROW2 sessEvil 60 >/dev/null 2>&1; [ $? -eq 1 ];     check "malformed expiry fails closed" $?
sed -i "s/^expiry=.*/expiry=$(( $(date +%s) + 60 ))/" "$ROOT/state/rows/ROW2.lease"
echo $(( $(date +%s) + 99999 )) > "$ROOT/state/.last_now"
lf_acquire ROW-CLK sessA 60 >/dev/null 2>&1; [ $? -eq 1 ];     check "backward clock: acquire refuses (monotonic floor)" $?
lf_renew ROW2 sessNew "$g4" 60 2>/dev/null; [ $? -eq 1 ];      check "backward clock: renew refuses" $?
floor_before=$(cat "$ROOT/state/.last_now")
lf_recover ROW2 >/dev/null
[ "$(cat "$ROOT/state/.last_now")" = "$floor_before" ];        check "read-only recovery never mutates the clock floor" $?
echo 0 > "$ROOT/state/.last_now"

# ---- 7: HALT — entry sweep AND the commit instant --------------------------------------------------
: > "$ROOT/state/HALT"
halt_fails=0
for op in "lf_acquire ROW3 sessH 60" "lf_renew ROW2 sessNew $g4 60" "lf_release ROW2 sessNew $g4" \
          "lf_start_job ROW2 sessNew $g4 JOBH" "lf_soft_trip ROW2 sessNew $g4" \
          "lf_compaction sessNew" "lf_commit_boundary ROW2 sessNew $g4" \
          "lf_consume_handoff ROW2 sessH" "lf_respawn ROW2 supervisor-token" \
          "lf_activity ROW2 sessNew $g4" "lf_safety_flag ROW2 sessNew $g4" \
          "lf_observe sessNew stale id ROW2 $g4 t1" "lf_kill_eligible sessNew id ROW2 $g4" \
          "lf_kill sessNew id ROW2 $g4" "lf_type sessNew hello" "lf_recover_finish ROW2"; do
    $op >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 9 ] || { echo "FAIL HALT did not stop: $op (rc=$rc)"; halt_fails=1; }
done
check "HALT entry sweep refuses every mutator (rc 9)" $halt_fails
rm -f "$ROOT/state/HALT"
# COMMIT-INSTANT: LF_HALT_AT=commit raises HALT after staging, immediately before publish —
# the operation must refuse and the lease must be unchanged.
before=$(cat "$ROOT/state/rows/ROW2.lease")
LF_HALT_AT=commit lf_renew ROW2 sessNew "$g4" 60 2>/dev/null; rc=$?
[ "$rc" -eq 9 ] && [ "$(cat "$ROOT/state/rows/ROW2.lease")" = "$before" ]
check "HALT raised at the COMMIT INSTANT (after staging) still stops the publish" $?
rm -f "$ROOT/state/HALT"
lf_respawn ROW2 supervisor-token >/dev/null    # a real counter, so activity has a removal to gate
LF_HALT_AT=commit lf_activity ROW2 sessNew "$g4" 2>/dev/null; rc=$?
[ "$rc" -eq 9 ] && [ -e "$ROOT/state/respawns/ROW2" ]
check "raw transitions (marker/counter removal) honor the commit gate too" $?
rm -f "$ROOT/state/HALT"
lf_activity ROW2 sessNew "$g4"                 # clean up the counter for later scenarios

# ---- 8: crash matrix — POINT-SPECIFIC oracles ---------------------------------------------------------
crash_fails=0
crash_case() {  # $1 point, $2 expected-recovery
    local point=$1 expect=$2
    local CR="$ROOT/crash-$point"
    mkdir -p "$CR"
    (
        . tests/lifecycle/proto.sh; lf_init "$CR" sup
        case "$point" in
            before-lease-write|after-lease-write)
                LF_CRASH_POINT=$point lf_acquire CROW s1 60 ;;
            before-job-write|after-job-write)
                g=$(lf_acquire CROW s1 60); LF_CRASH_POINT=$point lf_start_job CROW s1 "$g" CJOB ;;
            before-release|after-release)
                g=$(lf_acquire CROW s1 60); LF_CRASH_POINT=$point lf_release CROW s1 "$g" ;;
            before-handoff-write|after-handoff-write|after-boundary-release)
                g=$(lf_acquire CROW s1 60); lf_start_job CROW s1 "$g" CJOB
                LF_CRASH_POINT=$point lf_commit_boundary CROW s1 "$g" ;;
            before-consume|after-consume|after-successor-lease)
                g=$(lf_acquire CROW s1 60); lf_commit_boundary CROW s1 "$g"
                LF_CRASH_POINT=$point lf_consume_handoff CROW s2 ;;
        esac
    ) >/dev/null 2>&1
    local out rc=0
    out=$(LF_ROOT="$CR" lf_recover CROW)
    [ "$out" = "$expect" ] || rc=1
    local stray; stray=$(find "$CR" -name '.tmp.*' | wc -l)
    { [ "$rc" -eq 0 ] && [ "$stray" -eq 0 ]; } || { echo "FAIL crash@$point: recover='$out' want='$expect' stray=$stray"; crash_fails=1; }
}
crash_case before-lease-write     "released"
crash_case after-lease-write      "owner s1"
crash_case before-job-write       "owner s1"
crash_case after-job-write        "owner s1"
crash_case before-release         "owner s1"
crash_case after-release          "released"
crash_case before-handoff-write   "owner s1"
crash_case after-handoff-write    "owner s1"       # live lease wins; handoff unconsumable yet
crash_case after-boundary-release "handoff-ready"
crash_case before-consume         "handoff-ready"
crash_case after-consume          "consumed-by s2"
crash_case after-successor-lease  "owner s2"
check "crash matrix: every point recovers to its EXACT expected state, no stray temps" $crash_fails
# job presence is point-specific too
[ ! -e "$ROOT/crash-before-job-write/jobs/CJOB" ] && [ -e "$ROOT/crash-after-job-write/jobs/CJOB" ]
check "job record exists after its publish point and not before" $?
# interrupted consumption: a THIRD session's bare acquire refuses; only the recorded successor recovers
CR="$ROOT/crash-after-consume"
LF_ROOT="$CR" lf_acquire CROW s3 60 >/dev/null 2>&1; [ $? -eq 1 ]
check "interrupted consumption fences bare acquisition (the recorded successor is protected)" $?
fin=$(LF_ROOT="$CR" lf_recover_finish CROW)
[ "$fin" = "s2" ] && [ "$(LF_ROOT="$CR" lf_recover CROW)" = "owner s2" ]
check "recovery mints the lease for exactly the RECORDED successor" $?
# owner+handoff coexistence is not dual authority
CR="$ROOT/crash-after-handoff-write"
LF_ROOT="$CR" lf_consume_handoff CROW s3 >/dev/null 2>&1; [ $? -eq 1 ]
check "a handoff beside a live lease is unconsumable (no dual authority window)" $?
# a crash before the marker cleanup cannot strand the successor: consume clears the marker
CR="$ROOT/crash-mkr"; mkdir -p "$CR"
( . tests/lifecycle/proto.sh; lf_init "$CR" sup
  g=$(lf_acquire CROW s1 600); lf_soft_trip CROW s1 "$g"
  LF_CRASH_POINT=after-boundary-release lf_commit_boundary CROW s1 "$g" ) >/dev/null 2>&1
g9=$(LF_ROOT="$CR" lf_consume_handoff CROW s2)
LF_ROOT="$CR" lf_start_job CROW s2 "$g9" CJOB2 >/dev/null
check "a marker stranded by a boundary crash is cleared by consumption (successor can work)" $?

# ---- 9: doom loop ------------------------------------------------------------------------------------
lf_respawn ROW4 wrong-token 2>/dev/null; [ $? -eq 1 ];         check "respawn counting requires the supervisor token" $?
lf_respawn ROW4 supervisor-token; lf_respawn ROW4 supervisor-token
g7=$(lf_acquire ROW4 sessR 60)
lf_activity ROW4 sessR "$g7"
lf_respawn ROW4 supervisor-token; lf_respawn ROW4 supervisor-token
lf_respawn ROW4 supervisor-token; [ $? -eq 3 ];                check "third consecutive activity-free respawn dead-letters (rc 3)" $?
lf_respawn ROW4 supervisor-token 2>/dev/null; [ $? -eq 3 ];    check "no fourth automatic respawn" $?
dl_fails=0
for op in "lf_acquire ROW4 sessZ 60" "lf_renew ROW4 sessR $g7 60" "lf_release ROW4 sessR $g7" \
          "lf_start_job ROW4 sessR $g7 JOBD" "lf_commit_boundary ROW4 sessR $g7" \
          "lf_soft_trip ROW4 sessR $g7" "lf_activity ROW4 sessR $g7" "lf_consume_handoff ROW4 sessZ" \
          "lf_safety_flag ROW4 sessR $g7" "lf_observe sessR stale id ROW4 $g7 t9" \
          "lf_recover_finish ROW4"; do
    $op >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL dead-letter did not fence: $op"; dl_fails=1; }
done
check "a dead-letter fences EVERY row operation (incl. re-flag, observe, recover)" $dl_fails
lf_kill sessR id ROW4 "$g7" 2>/dev/null; [ $? -eq 1 ];         check "a dead-lettered row's session cannot be killed on stale authority" $?

# ---- 10: safety flag -----------------------------------------------------------------------------------
g5=$(lf_acquire ROW5 sessS 60)
lf_safety_flag ROW5 sessS "$((g5 + 7))" 2>/dev/null; [ $? -eq 1 ]; check "safety flag with a wrong generation refuses" $?
lf_safety_flag ROW5 sessOther "$g5" 2>/dev/null; [ $? -eq 1 ];  check "safety flag from a non-owner refuses (full CAS)" $?
lf_safety_flag ROW5 sessS "$g5";                                check "safety-flagged turn dead-letters immediately" $?
lf_start_job ROW5 sessS "$g5" JOBS 2>/dev/null; [ $? -eq 3 ];   check "no further row action after a safety dead-letter" $?
[ ! -e "$ROOT/state/deadletters/ROW6" ];                        check "the safety flag cannot touch a different row" $?

# ---- 11+12: kill discipline ------------------------------------------------------------------------------
g6=$(lf_acquire ROW6 sessK 600)
lf_observe sessK stale tmux-id-1 ROW6 "$g6" t1
lf_kill_eligible sessK tmux-id-1 ROW6 "$g6" 2>/dev/null; [ $? -eq 1 ]; check "ONE stale observation cannot kill" $?
lf_observe sessK stale tmux-id-1 ROW6 "$g6" t1
lf_kill_eligible sessK tmux-id-1 ROW6 "$g6" 2>/dev/null; [ $? -eq 1 ]; check "two observations sharing a tick label cannot kill (distinct ticks)" $?
lf_observe sessK unknown tmux-id-1 ROW6 "$g6" aaa   # lexically SMALL caller tick label
lf_kill_eligible sessK tmux-id-1 ROW6 "$g6" 2>/dev/null; [ $? -eq 1 ]
check "an 'unknown' vetoes by ARRIVAL ORDER even with a lexically earlier tick label (server sequencing)" $?
lf_observe sessK stale tmux-id-1 ROW6 "$g6" t3
lf_observe sessK stale tmux-id-OTHER ROW6 "$g6" t4
lf_kill_eligible sessK tmux-id-1 ROW6 "$g6" 2>/dev/null; [ $? -eq 1 ]; check "an identity mismatch in the last-two window vetoes" $?
lf_observe sessK stale tmux-id-1 ROW6 "$g6" t5
lf_observe sessK stale tmux-id-1 ROW6 "$g6" t6
: > "$ROOT/state/foreign-claude"
lf_kill sessK tmux-id-1 ROW6 "$g6" 2>/dev/null; [ $? -eq 1 ];   check "standby re-checked AT THE KILL (TOCTOU closed)" $?
rm -f "$ROOT/state/foreign-claude"
: > "$ROOT/state/foreign-claude"
lf_type sessY hello 2>/dev/null; [ $? -eq 1 ];                  check "typing/prompting is gated by standby exactly like a kill" $?
rm -f "$ROOT/state/foreign-claude"
lf_kill sessK tmux-id-1 ROW6 "$g6";                             check "repeated classified evidence, verified identity + generation: kill proceeds" $?
lf_release ROW6 sessK "$g6" && g6b=$(lf_acquire ROW6 sessK 600)
lf_kill_eligible sessK tmux-id-1 ROW6 "$g6b" 2>/dev/null; [ $? -eq 1 ]
check "old observations cannot be replayed against a NEW lease generation" $?

# ---- N=1 compaction ceiling ---------------------------------------------------------------------------
g8=$(lf_acquire ROW7 sessN 60)
lf_compaction sessN
lf_acquire ROW8 sessN 60 >/dev/null 2>&1; [ $? -eq 1 ];         check "after one classified compaction: no further row acquisition" $?
lf_start_job ROW7 sessN "$g8" JOBN 2>/dev/null; [ $? -eq 1 ];   check "a compacted session starts NO new job" $?
lf_renew ROW7 sessN "$g8" 60;                                   check "a compacted session may renew to reach its boundary" $?
lf_commit_boundary ROW7 sessN "$g8";                            check "a compacted session CAN (must) hand off and stop" $?
lf_consume_handoff ROW7 sessN >/dev/null 2>&1; [ $? -eq 1 ];    check "a compacted session cannot re-enter through handoff consumption (N=1 binds consume)" $?
lf_consume_handoff ROW7 sessFresh >/dev/null;                   check "a fresh session consumes the handoff normally" $?

# ---- 13: teardown FIRST, then the audited manifest ------------------------------------------------------
tmux -L "$SOCK" kill-server 2>/dev/null
tmux -L "$SOCK" has-session -t "$TMUX_SESSION" 2>/dev/null; [ $? -ne 0 ]
check "teardown: the private tmux server is gone (no live surrogate)" $?
TEARDOWN_ROOT="$ROOT"
STATE_SNAPSHOT_REMOVED=0
rm -rf "$TEARDOWN_ROOT/state" "$TEARDOWN_ROOT/fake-home" 2>/dev/null
[ ! -e "$TEARDOWN_ROOT/state" ] && STATE_SNAPSHOT_REMOVED=1
[ "$STATE_SNAPSHOT_REMOVED" -eq 1 ]
check "teardown: disposable state and fake credentials removed before the audit" $?
repo_writes=$(find . -path ./.git -prune -o -newer "$STAMP" -type f -print 2>/dev/null | wc -l)
[ "$repo_writes" -eq 0 ]
check "audit: ZERO repo-tree files (tracked, ignored, or untracked) written during the run" $?
END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- result manifest: built AFTER teardown+audit, binds the final failure status ------------------------
MANIFEST=$(
    echo "artifact proto.sh sha256=$(sha256sum tests/lifecycle/proto.sh | cut -d' ' -f1)"
    echo "artifact lifecycle_falsifier.sh sha256=$(sha256sum tests/lifecycle_falsifier.sh | cut -d' ' -f1)"
    echo "started=$START_TS finished=$END_TS"
    echo "scenarios=${#RESULTS[@]} failures=$fails"
    printf '%s\n' "${RESULTS[@]}"
    echo "teardown=private-tmux-server-killed state-removed=$STATE_SNAPSHOT_REMOVED repo-writes=$repo_writes"
    echo "exit_status=$fails"
)
printf '%s\n' "$MANIFEST"
echo "manifest_sha256=$(printf '%s\n' "$MANIFEST" | sha256sum | cut -d' ' -f1)"
# the optional evidence copy lands OUTSIDE the repo tree (audited above as zero writes) — the
# caller passes an absolute path such as the operator's evidence directory
[ -n "${LF_MANIFEST_OUT:-}" ] && printf '%s\n' "$MANIFEST" > "$LF_MANIFEST_OUT"

if [ "$fails" -ne 0 ]; then echo "FAIL lifecycle_falsifier.sh"; exit 1; fi
echo "PASS lifecycle_falsifier.sh"
