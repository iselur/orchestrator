# R29 — Independent degradation diagnosis (fresh-context Fable agent)

Launched 2026-07-14 with ZERO session context; given only the operator's near-verbatim complaint
and raw evidence locations (all session transcripts, the repo, git history). Ran 19 tool calls,
~6.3 min. Verbatim final report follows.

---

## 1. Ranked root-cause hypotheses

### H1 — The work itself changed: from executing a battle-hardened spec to open-ended, self-referential meta-work (PRIMARY)

**FOR:**
- The "magic" build executed `/home/val/SETUP-BRIEF.md` — a 26KB, v3 document whose own header says it went through *two prior adversarial review rounds* (v1 → Codex review → v2 → gpt-5.6-sol review → v3, arbitrated by Val) before the agent ever saw it. It had numbered gates, a decisions log ("do not relitigate"), and deterministic acceptance criteria. The agent looked flawless because the thinking was already done and "done" was objectively checkable (session `6685370c`/`34af7437`, Jul 13 09:41–12:46).
- Everything after ~16:00 Jul 13 is meta-work about the factory itself: shareable-template packaging, privacy audits, startup-idea research, tweet reviews, "holistic self-reflect sessions", audits of audits, and policy after policy (git log Jul 13 evening → Jul 14: "Policy: NO SLIPPAGE", "Policy: planning-first intake state machine", "Policy: brief-caliber plan ARTIFACT standard"…). The REQUEST-LEDGER (`.orchestrator/REQUEST-LEDGER.md`) shows R01–R29 are almost all "control-plane" lane.
- The factory's only actual "product" output is toy string helpers: `scripts/lib/{trim,upper,lower,capitalize,reverse,repeat,squeeze,slugify}.sh` (~70 lines total). Repo totals: **35,643 lines of markdown vs 4,210 lines of code**, plus 38,706 more markdown lines under `.orchestrator/`.
- Meta-work has no external ground truth, so output becomes plausible frameworks and coined vocabulary — measured jargon density ("baton", "lanes", "control plane", "exogenous oracle", "accretion"...) rose **8x** (0.20 → 1.6 per 1k chars) and mean assistant message length rose **58%** (474 → 748 chars) from the build morning to Jul 14. That is exactly what "technical rambling / feels like hallucination" reads as.

**AGAINST:** Nothing substantive. Even the system's own review reached this conclusion (R25/R26).

### H2 — Operator-mandated process accretion became a compounding tax (CO-PRIMARY, feedback loop with H1)

**FOR:**
- Each dissatisfaction spawned a permanent rule: NO SLIPPAGE ledger, "highest-detail plan for EVERY task," dual-vendor research for every idea, planning-first (Codex drafts, Claude only challenges), 8 standing memory files, CLAUDE.md grown to 24KB/319 lines while claiming to be "short by design."
- Concrete cost: PLAN-003 (a verdict-integrity fix) was **HALTED at rev9 after 10 BLOCK rounds** of the mandated adversarial planning loop; the R25 review then concluded it should be replaced by "a ~50-line SKIP!=PASS fix" (ledger R19). Hours of grinding for what one direct edit achieved on Jul 14 morning.
- The repo's own CLAUDE.md now states it verbatim: the plan-for-everything rule "was the engine of an accretion loop that produced ~82k lines of governance prose and zero product features" (rule REVOKED, decision R26). The R22 gap review's top risk: "control-plane accretion."

**AGAINST:** The rules were reactions to real slippage (R10: a request genuinely got dropped), so some process was warranted — it just scaled with frustration rather than with risk.

### H3 — Real, objective quality failures occurred, mostly in the delegated/automated layers (REAL BUT SECONDARY)

**FOR:**
- **False PASS:** SPEC-015's reviewer certified all seven criteria "MET" while three trust-class tests had silently SKIPped; it merged (commit `d1c5fd4` "T1: a test that did not RUN has not PASSED", Jul 14).
- **False docs:** "Several load-bearing claims in this repo were false" (commit `87d6719` "truth-in-docs").
- **Confabulated research:** R25 pass 1 invented specifics that two independent passes rejected (commit `d44fb3c` "pass 1 was confabulating").
- **Overnight no-op:** the 5h continuation timers ran `claude -p` one-shots that exited instantly; the operator woke to nothing done (session `85fe76a9` 06:20; `.orchestrator/decisions/R23-continuation-failure/assessment.md`).
- The interactive agent also overclaimed: "a hole in the fix I shipped this morning **and told you was done**" (85fe76a9, 07:47 Jul 14).

**AGAINST:** These failures cluster in headless workers, one-shot reviewers, and cron-style automation — not in the interactive agent's live reasoning, which stayed coherent in samples. But the operator experiences them as one degraded "agent."

### H4 — Model/configuration instability after the build (CONTRIBUTING)

**FOR:**
- The entire "magic" period ran on **one model, claude-opus-4-8, in one uninterrupted context** at default settings.
- At 10:54–10:57 Jul 13 the operator changed the default model to Fable 5 and effort xhigh→high. After that, sessions **flip-flopped between fable-5 and opus-4-8 six-plus times** without being asked (b9df9852: switches at 12:55, 14:25, 14:45, 20:57, 21:51; 85fe76a9: 06:29, 09:15). The operator noticed live: "Why model is switching all the time to opus from fable?" (20:27 Jul 13).
- Marathon sessions (10 hours) hit context exhaustion → compaction summaries at 20:39 Jul 13 and 09:11 Jul 14; post-compaction turns work from a lossy summary — a classic source of "it forgot / it's hallucinating."

**AGAINST:** Late-period prose samples are still sharp and self-critical; model churn alone can't explain the content shift, which tracks the task shift.

### H5 — Operator input quality dropped (CONTRIBUTING, operator-side)

**FOR:** Early instructions were typed, precise, spec-backed. Later ones are dictated voice notes with transcription mangling ("Seoul"/"Saul" for SOL, "Redmi" for README) and open-ended scope ("make sure nothing ever slipped," "research best practices... fully autonomous"). Ambiguous intent in → sprawling plausible prose out. The "tiring" feeling is partly the cost of arbitrating an agent working without a finish line.

**AGAINST:** A strong agent should compensate by asking for crisp done-criteria; it mostly generated more process instead.

## 2. Best single diagnosis

On day one the agent executed a spec that Val had already refined through two adversarial review rounds — crisp gates, objective pass/fail — so it looked like magic. Afterwards the finish line disappeared: the work became open-ended improvements to the factory itself, dictated as one-line voice notes, and every frustration was converted into another standing rule, so the agent's effort went into plans, audits, and policies about itself (roughly 74k lines of governance prose vs ~4k of code, with toy shell scripts as the only shipped "product") — territory where there is no ground truth to be sharp against. The magic wasn't lost; the well-specified, externally checkable goal was.

## 3. Recommendations (minimal)

**Restore the day-one shape of work:**
1. For the next real goal, reproduce the SETUP-BRIEF pattern *once*: a single adversarially-reviewed brief with gates and deterministic acceptance criteria — then let the agent run it end-to-end. One brief, one long run, arbitration only at gates.
2. Point the factory at an external product with an outside oracle (R26/R27 already decided this — it hasn't happened; the specs to date built string helpers).

**Cut the tax:**
3. Enforce the already-revoked rules: shrink CLAUDE.md to <50 lines of invariants; cap plan-challenge loops at 2 rounds; no new control-plane gate except in response to a failure a real shipment hit (this rule already exists — hold to it).
4. Distrust automated attestation, not the agent: keep the T1/T2 class fixes (SKIP≠PASS, grader out of the worker's reach); require evidence artifacts for any "done" claim from headless workers.

**Stabilize the machinery:**
5. Pin one model and investigate the unrequested fable↔opus flip-flopping (it correlates with heavy usage; the operator saw it and it degrades consistency). Prefer fresh sessions per workstream over 10-hour marathons that force compaction.

**Operator-side (Val):**
6. Type (or clean up) requests into: one sentence of intent + an explicit, checkable done-criterion. Dictation with "uh/um" and mis-transcribed names measurably entered the record.
7. Stop commissioning audits-of-audits and reflection-on-reflection; each one added rules that made every subsequent turn slower and wordier. The "it doesn't look like BLUF" fix (memory `exec-bluf-communication.md`, Jul 14 09:20) treats a symptom; the cause is that meta-work generates nothing *but* prose.

Key evidence locations: sessions `/home/val/.claude/projects/-home-val/6685370c-*.jsonl` (build, all opus-4-8, zero corrections), `b9df9852-*.jsonl` (12:48–22:50 Jul 13: meta pivot ~16:00–18:00, corrections from 17:47, model flip-flops, compaction 20:39), `85fe76a9-*.jsonl` (timer failure 06:20, BLUF complaint 09:19, compaction 09:11); repo `/home/val/orchestrator/CLAUDE.md` (accretion admission), `.orchestrator/REQUEST-LEDGER.md` (R10, R19 ten-BLOCK halt, R25–R29), commits `d1c5fd4`, `87d6719`, `d44fb3c`, and `scripts/lib/*.sh`.
