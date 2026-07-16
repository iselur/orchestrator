#!/usr/bin/env bash
# Program C reshape (R84): two properties of scripts/review on PLAN-NNN artifacts, with a stub
# codex binary (no network, no real reviewer invoked).
#
# (1) Plan authorship derives from the .md frontmatter's author_model via the models.json
#     vendor_map — spec_author is a ROLE, not a vendor, so the old unconditional-codex namespace
#     rule would misclassify the moment the owner flips roles.spec_author in models.json. A
#     Claude-authored plan proceeds to Codex review; a Sol-authored plan is still refused as
#     self-review (exit 4); broken provenance (missing sibling .md, missing frontmatter, an
#     unmapped model) is refused outright, never guessed.
# (2) Review round dirs BIND to the artifact identity: a PLAN-NNN context forces --topic plan-nnn,
#     so a renamed topic can no longer mint a fresh directory and reset the 5-round cap.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo/scripts" "$tmp/repo/.orchestrator"
cp -p scripts/review "$tmp/repo/scripts/review"
cp -p scripts/models.json "$tmp/repo/scripts/models.json"
cp -p scripts/models_check.py "$tmp/repo/scripts/models_check.py"
chmod u+w "$tmp/repo/scripts/models.json"

cat >"$tmp/bin/codex" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null   # consume the stdin prompt like the real CLI
sleep "${CODEX_STUB_SLEEP:-0}"
printf 'stub review verdict\n'
STUB
chmod +x "$tmp/bin/codex"

cd "$tmp/repo"
export PATH="$tmp/bin:$PATH"

# Fixtures --------------------------------------------------------------------------------------
# Frontmatter exactly as scripts/codex-plan writes it; only author_model varies.
mk_plan() { # $1 path, $2 author_model
  printf -- '---\nid: %s\ncreated: 2026-07-16T00:00:00Z\nauthor_model: %s\nstatus: draft\ntask: "fixture"\n---\n# fixture plan body\n' \
    "$(basename "${1%.md}")" "$2" > "$1"
}
mkdir -p .orchestrator/plans
mk_plan .orchestrator/plans/PLAN-101.md claude-opus-4-8
mk_plan .orchestrator/plans/PLAN-001.md gpt-5.6-sol
printf '# no frontmatter at all\n' > .orchestrator/plans/PLAN-003.md
mk_plan .orchestrator/plans/PLAN-004.md mystery-model-9
mk_plan .orchestrator/plans/PLAN-105.md claude-opus-4-8
printf 'raw stdout provenance\n' > .orchestrator/plans/PLAN-105.stdout
printf 'orphan stdout, no sibling md\n' > .orchestrator/plans/PLAN-106.stdout
mk_plan .orchestrator/plans/PLAN-107.md claude-opus-4-8
printf 'a plain claude-drafted note\n' > claude-note.md

# 1. A Claude-authored plan (frontmatter author_model -> vendor claude) proceeds to Codex review
#    under its bound topic, and the round is recorded.
scripts/review --topic plan-101 --author claude --context .orchestrator/plans/PLAN-101.md "review" >/dev/null 2>&1 \
  && ok "claude-authored plan reviews under its bound topic" || bad "claude-authored plan refused under its bound topic"
[ -f .orchestrator/reviews/plan-101/round-1.md ] \
  && ok "round 1 recorded under plan-101" || bad "no round-1.md under plan-101"

# 2. Topic binding: the SAME artifact under any other topic is refused (exit 6) and writes nothing —
#    this is the rename-resets-cap bypass, closed.
for wrong in plan-102 fresh-slug-reset; do
  scripts/review --topic "$wrong" --author claude --context .orchestrator/plans/PLAN-101.md "review" >/dev/null 2>&1
  rc=$?
  [ "$rc" = 6 ] && ok "renamed topic '$wrong' refused (exit 6)" || bad "renamed topic '$wrong' gave exit $rc, expected 6"
  [ -e ".orchestrator/reviews/$wrong" ] && bad "renamed topic '$wrong' still created review state" \
    || ok "renamed topic '$wrong' writes nothing"
done

# 3. Legacy Sol-authored plan: derivation says codex. Matching --author codex hits the self-review
#    vendor gate (exit 4); forged --author claude hits the mismatch gate (exit 6).
scripts/review --topic plan-001 --author codex --context .orchestrator/plans/PLAN-001.md "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 4 ] && ok "sol-authored plan refused as self-review (exit 4)" || bad "sol-authored plan gave exit $rc, expected 4"
scripts/review --topic plan-001 --author claude --context .orchestrator/plans/PLAN-001.md "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 6 ] && ok "forged --author claude on a sol plan refused (exit 6)" || bad "forged claude on sol plan gave exit $rc, expected 6"

# 4. Broken provenance refuses outright (fail closed), never guesses:
scripts/review --topic plan-003 --author claude --context .orchestrator/plans/PLAN-003.md "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && ok "plan without frontmatter refused (exit 2)" || bad "frontmatterless plan gave exit $rc, expected 2"
scripts/review --topic plan-004 --author claude --context .orchestrator/plans/PLAN-004.md "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && ok "plan with unmapped author_model refused (exit 2)" || bad "unmapped author_model gave exit $rc, expected 2"
scripts/review --topic plan-106 --author claude --context .orchestrator/plans/PLAN-106.stdout "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && ok "orphan .stdout without sibling .md refused (exit 2)" || bad "orphan .stdout gave exit $rc, expected 2"

# 5. A .stdout WITH its sibling .md derives from that sibling's frontmatter and binds the topic.
scripts/review --topic plan-105 --author claude --context .orchestrator/plans/PLAN-105.stdout "review" >/dev/null 2>&1 \
  && ok ".stdout derives claude from its sibling .md and reviews" || bad ".stdout with claude sibling refused"

# 6. Two distinct PLAN artifacts in one call are refused: one artifact per review, its rounds are
#    its cap.
scripts/review --topic plan-101 --author claude \
  --context .orchestrator/plans/PLAN-101.md --context .orchestrator/plans/PLAN-105.md "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && ok "two distinct plan IDs refused (exit 2)" || bad "two plan IDs gave exit $rc, expected 2"

# 7. A plan plus a supporting non-plan file (both claude) still binds to the plan's topic.
scripts/review --topic plan-101 --author claude \
  --context .orchestrator/plans/PLAN-101.md --context claude-note.md "review" >/dev/null 2>&1 \
  && ok "plan + supporting note reviews under the bound topic" || bad "plan + supporting note refused"
scripts/review --topic side-slug --author claude \
  --context .orchestrator/plans/PLAN-101.md --context claude-note.md "review" >/dev/null 2>&1
rc=$?
[ "$rc" = 6 ] && ok "plan + note under a renamed topic refused (exit 6)" || bad "plan + note renamed topic gave exit $rc, expected 6"

# 8. Non-plan contexts keep caller-chosen topics — behavior unchanged.
scripts/review --topic any-free-slug --author claude --context claude-note.md "review" >/dev/null 2>&1 \
  && ok "non-plan context keeps its caller-chosen topic" || bad "non-plan context refused under a free topic"

# 9. The 5-round cap holds for the BOUND topic under concurrency: six simultaneous invocations on
#    PLAN-107 (topic plan-107, rounds start fresh) must yield exactly five successes and one exit 3.
pids=()
for tag in a b c d e f; do
  CODEX_STUB_SLEEP=1 scripts/review --topic plan-107 --author claude \
    --context .orchestrator/plans/PLAN-107.md "concurrent $tag" >/dev/null 2>&1 & pids+=($!)
done
rcs=""
for p in "${pids[@]}"; do wait "$p"; rcs="$rcs $?"; done
rcs=$(echo "$rcs" | tr ' ' '\n' | sed '/^$/d' | sort -n | tr '\n' ' ' | sed 's/ $//')
[ "$rcs" = "0 0 0 0 0 3" ] && ok "bound-topic race: five successes, one refusal" || bad "bound-topic race statuses were '$rcs' (expected '0 0 0 0 0 3')"
n=$(find .orchestrator/reviews/plan-107 -name 'round-[0-9].md' | wc -l)
[ "$n" = 5 ] && ok "bound topic capped at 5 rounds under race" || bad "bound-topic race produced $n rounds (expected 5)"
# ...and the artifact cannot escape its spent cap through a rename (the exact old bypass).
scripts/review --topic plan-107-take2 --author claude --context .orchestrator/plans/PLAN-107.md "escape" >/dev/null 2>&1
rc=$?
[ "$rc" = 6 ] && ok "spent-cap artifact cannot escape via topic rename (exit 6)" || bad "cap escape via rename gave exit $rc, expected 6"

[ "$fails" -eq 0 ] && echo "PASS review_plan_authorship.sh" || echo "FAIL review_plan_authorship.sh"
exit "$fails"
