#!/usr/bin/env bash
# The review-round cap must live in code: a prose cap already lost once to a ten-round review loop
# (~10,000 lines of revisions later replaced by a ~50-line hand fix). scripts/review allows two
# rounds per topic, refuses the third, refuses Codex-authored artifacts (its reviewer is Codex),
# and must hold the cap under concurrent invocations. Codex is always a local stub here.
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
sleep "${CODEX_STUB_SLEEP:-0}"
printf 'stub review verdict\n'
STUB
chmod +x "$tmp/bin/codex"

cd "$tmp/repo"
export PATH="$tmp/bin:$PATH"

# 1. Bad slugs and missing/unknown authors are refused.
if scripts/review --topic 'Bad Slug!' --author claude x 2>/dev/null; then bad "accepted a non-slug topic"; else ok "refuses a non-slug topic"; fi
if scripts/review --topic demo-topic x 2>/dev/null; then bad "accepted a review with no --author"; else ok "refuses a missing --author"; fi
if scripts/review --topic demo-topic --author gemini x 2>/dev/null; then bad "accepted an unknown author"; else ok "refuses an unknown author"; fi

# 2. Codex-authored artifacts are refused — the reviewer IS Codex, and Codex never grades Codex.
scripts/review --topic demo-topic --author codex "review this codex plan" >/dev/null 2>&1
rc=$?
[ "$rc" = 4 ] && ok "Codex-authored artifact refused (exit 4)" || bad "Codex-on-Codex not refused (exit $rc)"
[ -e .orchestrator/reviews/demo-topic ] && bad "refused author still created state" || ok "author refusal writes nothing"

# 3. Round 1 and round 2 run and are recorded.
scripts/review --topic demo-topic --author claude "round one prompt" >/dev/null 2>&1 \
  && ok "round 1 runs" || bad "round 1 failed"
scripts/review --topic demo-topic --author claude "round two prompt" >/dev/null 2>&1 \
  && ok "round 2 runs" || bad "round 2 failed"
n=$(find .orchestrator/reviews/demo-topic -name 'round-*.md' | wc -l)
[ "$n" = 2 ] && ok "two rounds recorded" || bad "expected 2 recorded rounds, found $n"

# 4. Round 3 is refused with a distinct exit code and writes nothing.
scripts/review --topic demo-topic --author claude "round three prompt" >/dev/null 2>&1
rc=$?
[ "$rc" = 3 ] && ok "round 3 refused (exit 3)" || bad "round 3 not refused (exit $rc)"
n=$(find .orchestrator/reviews/demo-topic -name 'round-*.md' | wc -l)
[ "$n" = 2 ] && ok "refusal wrote nothing" || bad "refusal still wrote a round file"

# 5. The cap holds under concurrency: three simultaneous invocations on a fresh topic must yield
#    exactly two recorded rounds (unlocked counting would let all three claim a round).
CODEX_STUB_SLEEP=1 scripts/review --topic race-topic --author claude "concurrent a" >/dev/null 2>&1 &
CODEX_STUB_SLEEP=1 scripts/review --topic race-topic --author claude "concurrent b" >/dev/null 2>&1 &
CODEX_STUB_SLEEP=1 scripts/review --topic race-topic --author claude "concurrent c" >/dev/null 2>&1 &
wait
n=$(find .orchestrator/reviews/race-topic -name 'round-*.md' | wc -l)
[ "$n" = 2 ] && ok "concurrent invocations still cap at 2 rounds" || bad "race produced $n rounds (expected exactly 2)"

# 6. A different topic gets its own counter; empty prompts are refused.
scripts/review --topic other-topic --author claude "prompt" >/dev/null 2>&1 \
  && ok "independent counter per topic" || bad "second topic blocked by first topic's counter"
if printf '  \n' | scripts/review --topic empty-topic --author claude 2>/dev/null; then bad "accepted an empty prompt"; else ok "refuses an empty prompt"; fi

[ "$fails" -eq 0 ] && echo "PASS review_cap.sh" || echo "FAIL review_cap.sh"
exit "$fails"
