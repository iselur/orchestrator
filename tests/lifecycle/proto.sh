#!/usr/bin/env bash
# THROWAWAY lifecycle prototype (R77 / PLAN-007, earliest falsifiable proof) — round-3 revision.
# Disposable design under test; operates ONLY under a caller-owned temporary root (LF_ROOT);
# touches no production state; nothing outside tests/ may source it.
#
# Design rules (each falsifier-enforced):
# - IDENTIFIERS: every externally supplied id (row/session/job/identity/class/tick) is
#   [A-Za-z0-9._-]+ — no path escapes, no multiline field injection. Public read APIs
#   (lf_recover, lf_jobs_of_lease) sanitize too.
# - LOCKING: one flock ($LF_ROOT/.lock) serializes every mutation.
# - HALT: checked at entry AND at the COMMIT INSTANT of every durable transition (the last
#   action before mv/ln/rm). LF_HALT_AT=commit is a test hook that raises HALT after staging,
#   proving the boundary check. HALT outranks everything.
# - CLOCK: mutators use _lf_checked_now (fails closed on unreadable/backward time and advances
#   the monotonic floor); read-only paths use _lf_now_ro (never mutates; backward time reads as
#   unreadable and the caller fails toward the SAFE side — a lease reads as live).
# - DURABILITY: records are staged then atomically PUBLISHED (mv/ln). This gives atomic
#   visibility — one reader never sees a partial record; crash-durability across host power
#   loss is explicitly out of the prototype's scope and stated here, not claimed.
# - CAS: every row mutation by a session requires (session, generation) to match. Supervisor
#   ops (respawn) require the supervisor token. Dead-letters fence EVERY row operation,
#   including safety re-flags, observations, and kills.
# - HANDOFF: ledger-derived; exactly ONE handoff may exist per row; consumption validates row,
#   generation, predecessor, and job fields, refuses while the from-lease is live, refuses a
#   compacted successor (N=1), clears any rotation marker, records the successor durably BEFORE
#   minting its lease; an interrupted consumption fences bare acquisition until recovery mints
#   the RECORDED successor.
# - OBSERVATIONS: server-assigned monotonic sequence numbers order them (caller tick ids are
#   data, not order); class is enum-validated.
# - CRASH INJECTION: LF_CRASH_POINT=<name> exits 97 at the named point.
# Return codes: 0 ok; 1 refused; 3 dead-lettered; 9 HALT.

set -u

lf_init() {  # $1 root, $2 supervisor-token
    LF_ROOT="$1"
    mkdir -p "$LF_ROOT"/{rows,jobs,handoffs,consumed,deadletters,observations,respawns,killed}
    : > "$LF_ROOT/.lock"
    printf '%s' "${2:-supervisor}" > "$LF_ROOT/supervisor"
    printf '0' > "$LF_ROOT/.obs_seq"
}

_lf_id() {  # every argument must be a safe single-token identifier
    local a
    for a in "$@"; do
        case "$a" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
    done
}

_lf_crash() { [ "${LF_CRASH_POINT:-}" = "$1" ] && exit 97; return 0; }
_lf_halt()  { [ -e "$LF_ROOT/HALT" ] && return 9; return 0; }
_lf_dead()  { [ -e "$LF_ROOT/deadletters/$1" ] && return 3; return 0; }

_lf_commit_gate() {  # the COMMIT-INSTANT gate: runs the test hook, then re-checks HALT
    [ "${LF_HALT_AT:-}" = "commit" ] && : > "$LF_ROOT/HALT"
    _lf_halt || exit 9
}

_lf_checked_now() {  # MUTATOR clock: fail-closed monotonic floor, advances it
    local now last
    now=$(date +%s 2>/dev/null) || return 1
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    last=$(cat "$LF_ROOT/.last_now" 2>/dev/null || echo 0)
    [[ "$last" =~ ^[0-9]+$ ]] || return 1
    [ "$now" -lt "$last" ] && return 1
    printf '%s' "$now" > "$LF_ROOT/.last_now.tmp" && mv "$LF_ROOT/.last_now.tmp" "$LF_ROOT/.last_now"
    echo "$now"
}

_lf_now_ro() {  # READ-ONLY clock: never mutates; backward/unreadable time returns failure
    local now last
    now=$(date +%s 2>/dev/null) || return 1
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    last=$(cat "$LF_ROOT/.last_now" 2>/dev/null || echo 0)
    [[ "$last" =~ ^[0-9]+$ ]] || return 1
    [ "$now" -lt "$last" ] && return 1
    echo "$now"
}

_lf_write() {  # $1 path, stdin content — stage, then gate, then publish (mv)
    _lf_halt || exit 9
    local tmp
    tmp="$(mktemp "$(dirname "$1")/.tmp.XXXXXX")"
    cat > "$tmp"
    _lf_commit_gate
    mv "$tmp" "$1"
}

_lf_create() {  # $1 path, stdin content — stage, gate, publish exactly-once (ln); rc 1 if exists
    _lf_halt || exit 9
    local tmp
    tmp="$(mktemp "$(dirname "$1")/.tmp.XXXXXX")"
    cat > "$tmp"
    _lf_commit_gate
    if ln "$tmp" "$1" 2>/dev/null; then rm -f "$tmp"; return 0; fi
    rm -f "$tmp"; return 1
}

_lf_move() {  # $1 src, $2 dst — a raw durable transition gets the same commit gate
    _lf_commit_gate
    mv "$1" "$2"
}

_lf_remove() {  # $1 path — gated removal
    _lf_commit_gate
    rm -f "$1"
}

_lf_lease_field() {
    [ -f "$LF_ROOT/rows/$1.lease" ] || return 0
    sed -n "s/^$2=//p" "$LF_ROOT/rows/$1.lease"
}

_lf_cas() {
    [ "$(_lf_lease_field "$1" session)" = "$2" ] && [ "$(_lf_lease_field "$1" generation)" = "$3" ]
}

_lf_lease_live() {  # rc 0 when owned and not provably expired: malformed expiry OR an
    local sess exp now  # unreadable/backward clock reads as LIVE (fences, never grants)
    sess=$(_lf_lease_field "$1" session)
    [ -n "$sess" ] || return 1
    exp=$(_lf_lease_field "$1" expiry)
    [[ "$exp" =~ ^[0-9]+$ ]] || return 0
    now=$(_lf_now_ro) || return 0
    [ "$exp" -gt "$now" ]
}

_lf_pending_consumption() {  # $1 row — an interrupted consumption at the CURRENT generation
    local gen
    gen=$(_lf_lease_field "$1" generation); gen=${gen:-0}
    ls "$LF_ROOT/consumed/$1.gen$gen".* >/dev/null 2>&1
}

# ---- lease --------------------------------------------------------------------------------------
lf_acquire() {  # $1 row, $2 session, $3 ttl -> stdout: generation
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        local now gen
        now=$(_lf_checked_now) || exit 1
        [ -e "$LF_ROOT/compacted.$2" ] && exit 1        # N=1: no further acquisition
        [ -e "$LF_ROOT/rows/$1.rotate" ] && exit 1      # rotation pending
        ls "$LF_ROOT/handoffs/$1."gen* >/dev/null 2>&1 && exit 1  # unconsumed handoff pending
        _lf_pending_consumption "$1" && exit 1          # interrupted consumption: the recorded
        # successor owns recovery (lf_recover_finish); a bare grab would orphan it
        gen=$(_lf_lease_field "$1" generation); gen=${gen:-0}
        [[ "$gen" =~ ^[0-9]+$ ]] || exit 1
        _lf_lease_live "$1" && exit 1                   # live lease: the owner renews
        _lf_crash before-lease-write
        _lf_write "$LF_ROOT/rows/$1.lease" <<EOF
row=$1
generation=$((gen + 1))
session=$2
expiry=$((now + $3))
EOF
        _lf_crash after-lease-write
        echo $((gen + 1))
    ) 9>>"$LF_ROOT/.lock"
}

lf_renew() {  # $1 row, $2 session, $3 gen, $4 ttl
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        local now; now=$(_lf_checked_now) || exit 1
        _lf_write "$LF_ROOT/rows/$1.lease" <<EOF
row=$1
generation=$3
session=$2
expiry=$((now + $4))
EOF
    ) 9>>"$LF_ROOT/.lock"
}

lf_release() {  # $1 row, $2 session, $3 gen
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        _lf_crash before-release
        _lf_write "$LF_ROOT/rows/$1.lease" <<EOF
row=$1
generation=$3
session=
expiry=0
EOF
        _lf_crash after-release
    ) 9>>"$LF_ROOT/.lock"
}

# ---- session <-> job mapping ----------------------------------------------------------------------
lf_start_job() {  # $1 row, $2 session, $3 gen, $4 job
    _lf_id "$1" "$2" "$4" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        [ -e "$LF_ROOT/rows/$1.rotate" ] && exit 1
        [ -e "$LF_ROOT/compacted.$2" ] && exit 1
        _lf_crash before-job-write
        _lf_create "$LF_ROOT/jobs/$4" <<EOF || exit 1
row=$1
generation=$3
session=$2
EOF
        _lf_crash after-job-write
    ) 9>>"$LF_ROOT/.lock"
}

lf_jobs_of_lease() {  # $1 row, $2 gen — reverse trace
    _lf_id "$1" "$2" || return 1
    grep -l "^row=$1\$" "$LF_ROOT/jobs/"* 2>/dev/null \
        | xargs -r grep -l "^generation=$2\$" | xargs -rn1 basename
}

# ---- rotation signals -------------------------------------------------------------------------------
lf_soft_trip() {  # $1 row, $2 session, $3 gen
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        _lf_write "$LF_ROOT/rows/$1.rotate" <<EOF
row=$1
requested_by=$2
generation=$3
EOF
    ) 9>>"$LF_ROOT/.lock"
}

lf_compaction() {  # $1 session
    _lf_id "$1" || return 1
    _lf_halt || return 9
    ( flock -x 9; _lf_halt || exit 9; _lf_write "$LF_ROOT/compacted.$1" <<< "1" ) 9>>"$LF_ROOT/.lock"
}

# ---- safe boundary ----------------------------------------------------------------------------------
lf_commit_boundary() {  # $1 row, $2 session, $3 gen
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        local jobs
        jobs=$(lf_jobs_of_lease "$1" "$3" | paste -sd, -)
        _lf_crash before-handoff-write
        _lf_write "$LF_ROOT/handoffs/$1.gen$3" <<EOF
row=$1
from_generation=$3
from_session=$2
jobs=$jobs
source=ledger
EOF
        _lf_crash after-handoff-write
        _lf_write "$LF_ROOT/rows/$1.lease" <<EOF
row=$1
generation=$3
session=
expiry=0
EOF
        _lf_crash after-boundary-release
        # the rotation request is fulfilled by the handoff; consumption clears it too, so a
        # crash HERE cannot strand the successor behind a stale marker
        [ -e "$LF_ROOT/rows/$1.rotate" ] && _lf_remove "$LF_ROOT/rows/$1.rotate"
        true
    ) 9>>"$LF_ROOT/.lock"
}

lf_consume_handoff() {  # $1 row, $2 successor — one locked transaction, fully validated
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_lease_live "$1" && exit 1
        [ -e "$LF_ROOT/compacted.$2" ] && exit 1        # N=1 binds the CONSUME path too
        local n h now gen
        n=$(ls -1 "$LF_ROOT/handoffs/$1."gen* 2>/dev/null | wc -l)
        [ "$n" -eq 1 ] || exit 1                        # exactly one handoff, else fail closed
        h=$(ls -1 "$LF_ROOT/handoffs/$1."gen*)
        now=$(_lf_checked_now) || exit 1
        gen=$(_lf_lease_field "$1" generation); gen=${gen:-0}
        [[ "$gen" =~ ^[0-9]+$ ]] || exit 1
        # full validation: the handoff must be THIS row's, at THIS generation, ledger-derived,
        # from a named predecessor, carrying its job map field
        grep -q "^row=$1\$" "$h" || exit 1
        grep -q "^from_generation=$gen\$" "$h" || exit 1
        grep -q '^from_session=..*$' "$h" || exit 1
        grep -q '^jobs=' "$h" || exit 1
        grep -q '^source=ledger$' "$h" || exit 1
        _lf_crash before-consume
        _lf_move "$h" "$LF_ROOT/consumed/$(basename "$h").$2" || exit 1
        _lf_crash after-consume
        _lf_write "$LF_ROOT/rows/$1.lease" <<EOF
row=$1
generation=$((gen + 1))
session=$2
expiry=$((now + 300))
EOF
        _lf_crash after-successor-lease
        [ -e "$LF_ROOT/rows/$1.rotate" ] && _lf_remove "$LF_ROOT/rows/$1.rotate"
        echo $((gen + 1))
    ) 9>>"$LF_ROOT/.lock"
}

# ---- respawn / dead-letter ----------------------------------------------------------------------------
lf_respawn() {  # $1 row, $2 supervisor-token
    _lf_id "$1" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        [ "$2" = "$(cat "$LF_ROOT/supervisor")" ] || exit 1
        _lf_dead "$1" || exit 3
        local n=0 f="$LF_ROOT/respawns/$1"
        [ -f "$f" ] && n=$(cat "$f")
        [[ "$n" =~ ^[0-9]+$ ]] || exit 1
        n=$((n + 1))
        if [ "$n" -ge 3 ]; then
            _lf_write "$LF_ROOT/deadletters/$1" <<EOF
row=$1
reason=doom-loop: 3 consecutive respawns without recorded useful activity
EOF
            exit 3
        fi
        _lf_write "$f" <<< "$n"
    ) 9>>"$LF_ROOT/.lock"
}

lf_activity() {  # $1 row, $2 session, $3 gen
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        [ -e "$LF_ROOT/respawns/$1" ] && _lf_remove "$LF_ROOT/respawns/$1"
        true
    ) 9>>"$LF_ROOT/.lock"
}

lf_safety_flag() {  # $1 row, $2 session, $3 gen — immediate dead-letter; never rewrites one
    _lf_id "$1" "$2" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_cas "$1" "$2" "$3" || exit 1
        _lf_write "$LF_ROOT/deadletters/$1" <<EOF
row=$1
generation=$3
reason=safety-flagged turn
EOF
    ) 9>>"$LF_ROOT/.lock"
}

# ---- classified liveness -> kill --------------------------------------------------------------------
lf_observe() {  # $1 session, $2 class, $3 identity, $4 row, $5 gen, $6 tick-label
    _lf_id "$1" "$3" "$4" "$5" "$6" || return 1
    case "$2" in stale|unknown) ;; *) return 1 ;; esac   # enum-validated class
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$4" || exit 3
        local seq
        seq=$(cat "$LF_ROOT/.obs_seq"); seq=$((seq + 1))
        _lf_write "$LF_ROOT/.obs_seq" <<< "$seq"
        # server-assigned zero-padded sequence orders observations; the caller's tick label is
        # DATA (used only for the distinct-tick rule), never ordering
        _lf_write "$LF_ROOT/observations/$1.$(printf '%08d' "$seq")" <<EOF
class=$2
identity=$3
row=$4
generation=$5
tick=$6
EOF
    ) 9>>"$LF_ROOT/.lock"
}

_lf_kill_ok() {  # $1 session, $2 identity, $3 row, $4 gen — inside-lock eligibility
    local session=$1 identity=$2 row=$3 gen=$4 last2 f t1 t2
    [ -e "$LF_ROOT/foreign-claude" ] && return 1
    _lf_dead "$row" && :; [ -e "$LF_ROOT/deadletters/$row" ] && return 1
    last2=$(ls -1 "$LF_ROOT/observations/$session."* 2>/dev/null | sort | tail -2)
    [ "$(printf '%s\n' "$last2" | grep -c .)" -eq 2 ] || return 1
    t1=$(sed -n 's/^tick=//p' "$(printf '%s\n' "$last2" | head -1)")
    t2=$(sed -n 's/^tick=//p' "$(printf '%s\n' "$last2" | tail -1)")
    [ -n "$t1" ] && [ -n "$t2" ] && [ "$t1" != "$t2" ] || return 1
    for f in $last2; do
        [ "$(sed -n 's/^class=//p' "$f")" = "stale" ] || return 1
        [ "$(sed -n 's/^identity=//p' "$f")" = "$identity" ] || return 1
        [ "$(sed -n 's/^row=//p' "$f")" = "$row" ] || return 1
        [ "$(sed -n 's/^generation=//p' "$f")" = "$gen" ] || return 1
    done
    _lf_cas "$row" "$session" "$gen"
}

lf_kill_eligible() {  # advisory probe
    _lf_id "$1" "$2" "$3" || return 1
    _lf_halt || return 9
    ( flock -x 9; _lf_halt || exit 9; _lf_kill_ok "$1" "$2" "$3" "$4" ) 9>>"$LF_ROOT/.lock"
}

lf_kill() {  # the ACTION revalidates HALT, standby, dead-letter, evidence, identity, generation
    _lf_id "$1" "$2" "$3" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_kill_ok "$1" "$2" "$3" "$4" || exit 1
        _lf_write "$LF_ROOT/killed/$1" <<< "row=$3 gen=$4 identity=$2"
    ) 9>>"$LF_ROOT/.lock"
}

lf_type() {  # $1 session, $2 text — prompt/keystroke op, gated like a kill
    _lf_id "$1" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        [ -e "$LF_ROOT/foreign-claude" ] && exit 1
        _lf_write "$LF_ROOT/typed.$1" <<< "$2"
    ) 9>>"$LF_ROOT/.lock"
}

# ---- crash recovery -----------------------------------------------------------------------------------
lf_recover() {  # $1 row -> ONE answer; read-only (never advances the clock floor)
    _lf_id "$1" || return 1
    (
        flock -x 9
        local sess gen c
        sess=$(_lf_lease_field "$1" session)
        gen=$(_lf_lease_field "$1" generation); gen=${gen:-0}
        if [ -n "$sess" ] && _lf_lease_live "$1"; then
            echo "owner $sess"
        elif ls "$LF_ROOT/handoffs/$1."gen* >/dev/null 2>&1; then
            echo "handoff-ready"
        elif c=$(ls -1 "$LF_ROOT/consumed/$1.gen$gen".* 2>/dev/null | tail -1); [ -n "$c" ]; then
            echo "consumed-by ${c##*.}"
        else
            echo "released"
        fi
    ) 9>>"$LF_ROOT/.lock"
}

lf_recover_finish() {  # $1 row — mint the lease for the RECORDED successor, nobody else
    _lf_id "$1" || return 1
    _lf_halt || return 9
    (
        flock -x 9
        _lf_halt || exit 9
        _lf_dead "$1" || exit 3
        _lf_lease_live "$1" && exit 1
        local c now gen
        gen=$(_lf_lease_field "$1" generation); gen=${gen:-0}
        c=$(ls -1 "$LF_ROOT/consumed/$1.gen$gen".* 2>/dev/null | tail -1)
        [ -n "$c" ] || exit 1
        now=$(_lf_checked_now) || exit 1
        _lf_write "$LF_ROOT/rows/$1.lease" <<EOF
row=$1
generation=$((gen + 1))
session=${c##*.}
expiry=$((now + 300))
EOF
        echo "${c##*.}"
    ) 9>>"$LF_ROOT/.lock"
}
