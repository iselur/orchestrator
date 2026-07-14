#!/usr/bin/env bash
# The bloat guard. This repo once held ~39,000 lines of process prose against ~4,000 lines of
# code, and the operator stopped understanding his own system. Standing prose is now allowlisted
# and capped; git history keeps everything deleted. Growing past a cap must be a deliberate,
# reviewed edit to this test — never drift.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v git >/dev/null 2>&1 || { echo "SKIP prose_cap.sh: git absent"; exit 77; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SKIP prose_cap.sh: not a git checkout"; exit 77; }

fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=1; }

# 1. Every tracked markdown file must be on the allowlist. A new standing document is a reviewed
#    decision: add it here AND give it a cap below, in the same PR.
declare -A cap=(
  [CLAUDE.md]=80
  [AGENTS.md]=45
  [README.md]=100
  [BOOTSTRAP.md]=80
  [SECURITY.md]=100
  [DECISIONS.md]=60
  [.orchestrator/BACKLOG.md]=40
  [.orchestrator/VISION.md]=40
)
total=0
while IFS= read -r f; do
  lines=$(wc -l < "$f")
  total=$((total + lines))
  if [ -z "${cap[$f]:-}" ]; then
    bad "tracked markdown outside the allowlist: $f — standing prose is allowlisted; put content in an existing file or add it here as a reviewed decision"
  elif [ "$lines" -gt "${cap[$f]}" ]; then
    bad "$f is $lines lines — cap is ${cap[$f]}. Delete before you add."
  else
    ok "$f: $lines/${cap[$f]} lines"
  fi
done < <(git ls-files '*.md')

# 2. Total standing prose stays under 600 lines.
if [ "$total" -le 600 ]; then
  ok "total tracked markdown: $total/600 lines"
else
  bad "total tracked markdown is $total lines — cap is 600. Delete before you add."
fi

# 3. The prose graveyards stay empty: plans and review rounds are untracked working files;
#    a decision that still binds gets one line in DECISIONS.md.
if git ls-files .orchestrator/decisions .orchestrator/plans .orchestrator/reviews | grep -q .; then
  bad "tracked files under .orchestrator/{decisions,plans,reviews} — these are transient; conclusions go to DECISIONS.md, arguments to the PR"
else
  ok "no tracked files under .orchestrator/{decisions,plans,reviews}"
fi

# 4. Backlog item #1 points outside this repo (a product, not this system). The one measured
#    failure mode of this setup was pointing itself at itself.
first_item=$(grep -A2 -m1 '^1\.' .orchestrator/BACKLOG.md 2>/dev/null)
if printf '%s' "$first_item" | grep -qE 'orchestrator-private|https?://|[A-Za-z0-9_-]+/[A-Za-z0-9_-]+#|its own repo'; then
  ok "backlog item #1 references something outside this repo"
else
  bad "backlog item #1 does not reference an external product/repo/URL — improving this system is never item #1 (CLAUDE.md rule 2)"
fi

[ "$fails" -eq 0 ] && echo "PASS prose_cap.sh" || echo "FAIL prose_cap.sh"
exit "$fails"
