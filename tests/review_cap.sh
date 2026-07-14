#!/usr/bin/env bash
# The review-round cap must live in code: a prose cap already lost once to a ten-round review loop
# (~10,000 lines of revisions later replaced by a ~50-line hand fix). scripts/review allows two
# rounds per topic and refuses the third. Codex is always a local stub here.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo/scripts" "$tmp/repo/.orchestrator"
cp -p scripts/review "$tmp/repo/scripts/review"

cat >"$tmp/bin/codex" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null   # consume the stdin prompt like the real CLI
printf 'stub review verdict\n'
STUB
chmod +x "$tmp/bin/codex"

cd "$tmp/repo"
export PATH="$tmp/bin:$PATH"

# 1. Bad slugs are refused.
if scripts/review --topic 'Bad Slug!' x 2>/dev/null; then bad "accepted a non-slug topic"; else ok "refuses a non-slug topic"; fi

# 2. Round 1 and round 2 run and are recorded.
scripts/review --topic demo-topic "round one prompt" >/dev/null 2>&1 \
  && ok "round 1 runs" || bad "round 1 failed"
scripts/review --topic demo-topic "round two prompt" >/dev/null 2>&1 \
  && ok "round 2 runs" || bad "round 2 failed"
n=$(find .orchestrator/reviews/demo-topic -name 'round-*.md' | wc -l)
[ "$n" = 2 ] && ok "two rounds recorded" || bad "expected 2 recorded rounds, found $n"

# 3. Round 3 is refused with a distinct exit code and writes nothing.
scripts/review --topic demo-topic "round three prompt" >/dev/null 2>&1
rc=$?
[ "$rc" = 3 ] && ok "round 3 refused (exit 3)" || bad "round 3 not refused (exit $rc)"
n=$(find .orchestrator/reviews/demo-topic -name 'round-*.md' | wc -l)
[ "$n" = 2 ] && ok "refusal wrote nothing" || bad "refusal still wrote a round file"

# 4. A different topic gets its own counter.
scripts/review --topic other-topic "prompt" >/dev/null 2>&1 \
  && ok "independent counter per topic" || bad "second topic blocked by first topic's counter"

# 5. Empty prompt refused.
if printf '  \n' | scripts/review --topic empty-topic 2>/dev/null; then bad "accepted an empty prompt"; else ok "refuses an empty prompt"; fi

[ "$fails" -eq 0 ] && echo "PASS review_cap.sh" || echo "FAIL review_cap.sh"
exit "$fails"
