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
patterns=$(grep -v '^#' -- "$LIST" | grep -v '^[[:space:]]*$')
[ -n "$patterns" ] || { echo "FAIL plain_language.sh: $LIST has no patterns — the sweep would be vacuous"; exit 1; }

# A malformed pattern must fail the test, never silently disable the sweep: grep exits 2 on a bad
# regex, and only 0 (match) / 1 (no match) are acceptable outcomes below.
printf '%s\n' "$patterns" | grep -qiEf /dev/stdin -- /dev/null
[ $? -le 1 ] || { echo "FAIL plain_language.sh: invalid regex in $LIST"; exit 1; }

mapfile -t md_files < <(git ls-files | grep -iE '\.(md|markdown|mdown|mkd)$')
[ "${#md_files[@]}" -gt 0 ] || { echo "FAIL plain_language.sh: no tracked markdown found — scan broken"; exit 1; }

for f in "${md_files[@]}"; do
  hits=$(printf '%s\n' "$patterns" | grep -inEf /dev/stdin -- "$f"); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL: banned term in $f (plain words or a name of real code, please):"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fails=1
  elif [ "$rc" -ge 2 ]; then
    echo "  FAIL: grep error scanning $f (exit $rc) — a check that cannot run must not pass"
    fails=1
  fi
  # "SOL" is case-sensitive: the lowercase model id gpt-5.6-sol in config lines is fine; the
  # uppercase character name that colonized the old prose is not.
  hits=$(grep -nE -- '\bSOL\b' "$f"); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL: 'SOL' used as a name in $f — say 'Codex'; the model id belongs only in config/scripts:"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fails=1
  elif [ "$rc" -ge 2 ]; then
    echo "  FAIL: grep error scanning $f (exit $rc) — a check that cannot run must not pass"
    fails=1
  fi
done

[ "$fails" -eq 0 ] && echo "PASS plain_language.sh" || echo "FAIL plain_language.sh"
exit "$fails"
