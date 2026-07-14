#!/usr/bin/env bash
# Plain-language guard (CLAUDE.md rule 4). The pre-reset repo coined so much private vocabulary
# ("oracle", "baton", decision codenames cited like law) that the operator stopped understanding
# his own system. Standing prose must be readable by a newcomer: banned terms fail CI.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v git >/dev/null 2>&1 || { echo "SKIP plain_language.sh: git absent"; exit 77; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SKIP plain_language.sh: not a git checkout"; exit 77; }

LIST=tests/banned-terms.txt
[ -f "$LIST" ] || { echo "FAIL plain_language.sh: $LIST missing"; exit 1; }

fails=0
patterns=$(grep -v '^#' "$LIST" | grep -v '^[[:space:]]*$')

# Case-insensitive sweep over every tracked markdown file.
while IFS= read -r f; do
  hits=$(grep -inE -f <(printf '%s\n' "$patterns") "$f" || true)
  if [ -n "$hits" ]; then
    echo "  FAIL: banned term in $f (plain words or a name of real code, please):"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fails=1
  fi
done < <(git ls-files '*.md')

# "SOL" is case-sensitive (the lowercase model id gpt-5.6-sol in config lines is fine; the
# uppercase character name that colonized the old prose is not).
while IFS= read -r f; do
  hits=$(grep -nE '\bSOL\b' "$f" || true)
  if [ -n "$hits" ]; then
    echo "  FAIL: 'SOL' used as a name in $f — say 'Codex'; the model id belongs only in config/scripts:"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fails=1
  fi
done < <(git ls-files '*.md')

[ "$fails" -eq 0 ] && echo "PASS plain_language.sh" || echo "FAIL plain_language.sh"
exit "$fails"
