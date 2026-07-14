#!/usr/bin/env bash
# R29 rule 1: no task starts without a goal AND a checkable definition of done.
# scripts/intake is the gate; these assertions prove it refuses incomplete intake.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/.orchestrator"
cp scripts/intake "$tmp/scripts/intake"
cat > "$tmp/.orchestrator/REQUEST-LEDGER.md" <<'EOF'
| id | date | request | lane | plan-ref | status | completion-evidence |
| R7 | 07-14 | existing row | — | — | done | — |
EOF

cd "$tmp"

# 1. No definition of done -> refused.
if bash scripts/intake -g "some goal" 2>/dev/null; then bad "accepted intake with NO definition of done"; else ok "refuses intake without definition of done"; fi

# 2. No goal -> refused.
if bash scripts/intake -d "done when tests pass" 2>/dev/null; then bad "accepted intake with NO goal"; else ok "refuses intake without goal"; fi

# 3. Vacuous done-criterion -> refused.
if bash scripts/intake -g "goal" -d "done" 2>/dev/null; then bad "accepted a vacuous done-criterion"; else ok "refuses a vacuous done-criterion"; fi

# 4. Complete intake -> accepted, id increments from the highest existing row, row is recorded.
id=$(bash scripts/intake -g "ship the fix" -d "done when tests/x.sh passes in CI") || id=""
[ "$id" = "R8" ] && ok "issues next id (R8 after R7)" || bad "wrong id: '$id'"
grep -q "R8 .*ship the fix.*DONE WHEN: done when tests/x.sh passes in CI" .orchestrator/REQUEST-LEDGER.md \
  && ok "row recorded with DONE WHEN" || bad "row not recorded correctly"

# 5. Refusals leave the ledger untouched.
rows_before=$(wc -l < .orchestrator/REQUEST-LEDGER.md)
bash scripts/intake -g "another goal" 2>/dev/null
rows_after=$(wc -l < .orchestrator/REQUEST-LEDGER.md)
[ "$rows_before" = "$rows_after" ] && ok "refused intake writes nothing" || bad "refused intake still wrote to the ledger"

[ "$fails" -eq 0 ] && echo "PASS intake_gate.sh" || echo "FAIL intake_gate.sh"
exit "$fails"
