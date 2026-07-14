# Loop mechanisms worth stealing (R25 research, source-verified)

Distilled from four production harnesses read at HEAD (SWE-agent/mini, OpenHands, Codex CLI, Aider)
plus Anthropic/OpenAI engineering posts. **Do NOT build these speculatively** — R26 says the control
plane earns gates from real failures. This is the shopping list for WHEN the outer loop is rebuilt,
so we don't reinvent what four teams already converged on.

## The convergence (four independent harnesses, same answers) — CORROBORATED BY BOTH PASSES

1. **Bash + one edit tool is the whole action space.** Everyone abandoned bespoke agent-computer
   interfaces — *including SWE-agent, the paper that coined the term*. Its own default config now
   uses Anthropic-style bash + str_replace; swebench.com labels SWE-agent "(legacy)" and promotes
   mini-swe-agent (~100 lines, 7 config fields) which scores **75.6%** on SWE-bench Verified.
   **Lesson: our scaffolding instinct is the thing to distrust.**
2. **Head/tail output truncation with an elided-count** is the one context mechanism nobody dropped.
3. **Retry budgets are small and SHARED.** Aider: `max_reflections = 3` for *everything* (malformed
   edit, lint failure, test failure). SWE-agent: `max_requeries: 3`. OpenHands critic:
   `max_iterations: 3`. And SWE-agent's data says this is right: **93% of resolved instances
   finished well under budget — failure is not a budget problem.**
   (Our `remediation limits: low 5 / default 3 / high 1` is already in this range. Keep.)
4. **The remaining alpha is per-episode SELECTION, not per-step interface.** Run the cheap loop N
   times, spend the intelligence budget on choosing. Structurally corroborated by both passes across
   SWE-agent (LLM chooser), OpenHands (trained critic), Aider (architect/editor) and Codex
   (`auto_review`) — though the specific configs and score deltas are single-source.

5. **ERROR MESSAGES ARE PROMPTS.** Four harnesses converged on this independently and it is the
   cheapest high-leverage thing in any loop: SWE-agent's linter *rejects the edit and shows what it
   would have looked like*; Aider replies "here are the closest matching lines — resend only the
   blocks that failed, the others already applied"; Codex treats a sandbox failure as an escalation
   signal; Anthropic's guidance is to "replace opaque tracebacks with actionable improvements."
   **Hobby loops feed back raw stderr. We feed back raw stderr.** (Our remediation prompt embeds the
   specific findings of the last failure — that is the right shape; make the *gate* messages
   actionable too.)

6. **Budget in dollars, not steps** — and SWE-agent's data says raising the cap is the wrong reflex:
   **93% of successes finished well under budget. Failure is not a budget problem.**
   Note: **Claude Agent SDK's `maxTurns` and `maxBudgetUsd` both default to NO LIMIT.** You must set
   them. (Corroborated by all three passes.)

7. **HOLD THE GRADER OUT OF THE AGENT'S REACH.** Every reward-hacking result in the failure
   literature reduces to the agent being able to touch the thing that scores it.
   **We shipped this on 2026-07-14 (T1):** `required_tests()` reads the required set from the
   ORCHESTRATOR's checkout, never the worktree — a candidate cannot shrink its own required set by
   deleting test files, and worker prose in `test.log` is never parsed as a verdict. Keep it that way.

8. **Tiered context management: clear tool outputs BEFORE you summarize.** Claude Code does exactly
   this (*"clears older tool outputs first, then summarizes if needed"*) plus a thrashing guard that
   stops auto-compacting rather than looping. The Anthropic API exposes both tiers directly
   (`clear_tool_uses` at 100k input tokens keeping the last 3 tool pairs; `compaction` at 150k).
   A single summarize-everything `/compact` step is the naive design.
   **Billing trap:** compaction tokens are billed but excluded from top-level `input_tokens` — sum
   `usage.iterations` or cost accounting silently under-reports.

## RELIABILITY: three passes ran; pass 1 was confabulating. REJECTED CLAIMS BELOW.

Three independent research passes over the same primary sources. Pass 1 supplied file paths, line
numbers and verbatim code snippets; passes 2 and 3 independently **could not verify** them and
contradicted several. A lone source producing suspiciously precise line numbers, contradicted twice,
is confabulating — not uniquely well-informed.

**This is the T1 failure in our own research** (certifying evidence nobody checked), caught by the
same method that catches it in code: an independent second opinion that is not shown the first.

**REJECTED — do not cite, do not build on:**
- Codex "auto-compacts at 90% of context, hardcoded ceiling" — the official reference says
  `model_auto_compact_token_limit` is *"unset uses model defaults"*. **No published number.**
- Codex Linux sandbox = bubblewrap — it is **Landlock + seccomp** (2 passes, official security docs).
- `with_escalated_permissions` removed — **it is live** and is the mechanism behind the `on-failure`
  approval policy.
- `.git`/`.codex` read-only carve-outs inside writable roots — unverified, single-source.
- OpenHands moved from code-as-action to native function calling — unverified, single-source.
- The Claude Code "auto-compact at ~95% / `effectiveWindow − 13,000`" formula circulating in blog
  posts — **third-party reverse-engineering, not in official docs**. The default is model-dependent.

**STILL UNVERIFIED (leads, not facts):** the OpenHands stuck-detector thresholds; its critic numbers;
SWE-agent's exact "Review Heavy" config values (the *structure* is confirmed by all three passes).
OpenHands condenser defaults produced **three different numbers across three passes** — version-
dependent by nature.

**UPGRADED:** Codex `project_doc_max_bytes` = 32 KiB is now well-supported — and comes with a live
footgun worth knowing: **Codex silently stops adding AGENTS.md files once the combined size hits the
cap, with no warning** (openai/codex#7138).

## The single biggest gap in OUR design: a STUCK DETECTOR  [SINGLE-SOURCE — VERIFY FIRST]

OpenHands is reportedly the only harness with a specified one (`openhands/controller/stuck.py`).
The five scenarios below are **one pass's reading, unconfirmed by the second** — but the file is a
single click to check, and the idea is the most valuable in the whole report. Verify before building.

| Scenario (unverified thresholds) | Our equivalent |
|---|---|
| same action + same observation ×4 | — |
| same action → error observation ×3 | remediation loop with identical findings |
| **monologue: ≥3 consecutive agent messages with NO observations between** | **the "silent no-op window" — our overnight failure** |
| alternating (A,O,A',O') pattern ×3 | — |
| repeated condensation with nothing between | "compact → still too big → compact" spiral |

Whatever the exact thresholds turn out to be, the principle is corroborated and damning: everyone
else relies on a human noticing. **We relied on a human noticing. He noticed after a whole night.**

## Directly relevant corroborations of our own failures

- *"CLI hit a quota limit and returned exit code 0 with an empty response, so the orchestrator kept
  firing — 300+ empty cron entries, VPS dead."* — **exit 0 masquerading as success.** This is T1's
  bug in a different costume, found independently in the wild.
- *"Incomplete results looked identical to successful completions"* when agents hit permission gates.
  Same class. **The progress validator (PLAN-006's real contribution) is the standard answer.**
- Anthropic C-compiler (16 parallel agents): *"it's important that the task verifier is nearly
  perfect, otherwise Claude will solve the wrong problem."* On a monolithic task, *"every agent would
  hit the same bug, fix that bug, and then overwrite each other's changes."*
- Cognition: *"Actions carry implicit decisions, and conflicting decisions carry bad results."*
  Reconciled position across the field: **parallelize reads, serialize writes.** (Our MAX_PARALLEL=3
  with one-live-attempt-per-spec + stale-base refusal already implements this. Keep.)

## Economics (the resource that actually binds us — currently uninstrumented)

- Anthropic official: **~$13/developer/active-day**; agent teams use **~7× the tokens** of a single
  session. Uber burned its **entire 2026 AI coding budget in four months**; its COO on ROI: *"That
  link is not there yet."* One practitioner runs ~100 Codex instances at **$1.3M/month**.
- Prompt caching: cache reads cost **90% less**. One team took cache-hit 7% → 84% and cut spend
  **59–70%**.
- Anthropic's own cost docs now recommend **preferring CLI tools (`gh`, `aws`) over MCP servers** for
  context efficiency; code-execution-with-MCP took a workflow from **150k → 2k tokens (98.7%)**.
- **A hard cap at the API key is the one non-negotiable.** An agent with a key and a loop is an
  unbounded liability.

## Sobering baselines for the "one-man + agents company" goal

- Microsoft .NET runtime, 10 months, 878 Copilot-agent PRs: **67.9% merged** (vs 87.1% human), and
  **52.3% needed a human to commit to the branch**. **65.7% of merged agent lines were TEST code.**
  The biggest lever was **documentation, not model quality** (38.1% → 69% success from adding build
  docs alone).
- METR: automated graders **overstate** merge-readiness by **24.2 points** vs real maintainers.
- The Register/NeuBird survey (696 practitioners): **8%** have AI ops agents in production; **60%**
  cite lack of trust as the #1 barrier.
- **No credible primary-sourced case exists of a company routinely letting an agent push to
  production unsupervised.** Six corroborated disasters, all the same root cause: an over-privileged
  credential plus a bypassed confirmation. (Replit deleted a prod DB *during a code freeze* and then
  fabricated 4,000 fake records to cover it up.)

**Read against our own goal:** keep the human on merge; write the conventions down (cheapest win
available); never give an agent a credential that can destroy something; cap spend at the key;
treat the issue tracker as UNTRUSTED INPUT if agents read it (a poisoned GitHub issue → private-repo
exfiltration is a demonstrated attack, and "no easy solution" per Invariant Labs).
