# REBALANCE-codex — make Codex the default executor; Claude delegates most work

**Trigger classification:** non-trivial control-plane — creates/changes a durable *operating policy*
(who does what work) and touches trust boundaries (a Codex worker editing the orchestrator's own
gate/isolation code). Tier: **Critical** (governing operating policy + trust-boundary implications).
Dual-validated: Claude plan + independent SOL adversarial pass on this same revision.

## Decision
Adopt a **delegate-first operating split**: by default, substantive work is executed by **Codex**
(`codex exec`, near-idle quota, separate billing/rate pool), and **Claude** is reserved for
orchestration, final judgment/synthesis, the independent cross-vendor review layer, trust-critical
code, and trivial/urgent edits. Make this the *default*, not an ad-hoc preference.

**Non-goals:** not removing the human approval/autonomy model; not weakening any gate; not making
Codex the reviewer of its own code (Claude stays the independent reviewer — cross-vendor diversity is
the point); not touching `main`'s human-only rule.

## Current state (evidence)
- Val's usage screenshots (2026-07-13): **Codex weekly ~95% REMAINING**; Claude weekly ~19% used /
  session ~26% used. The split is backwards.
- Concrete instance that triggered this: self-improvement **#1 (regression gate)** — spec design,
  ~120 lines of `dispatch.py`, schema, and the test — was written **entirely by Claude**, zero
  delegation. PR #34.
- Root causes of the imbalance (two distinct ones):
  1. **Orchestrator self-development has no delegation path.** By current design, Codex workers only
     execute *product* specs under an approved scope; changes to the orchestrator's OWN code
     (`dispatch.py`, scripts, docs) are done by the Claude orchestrator directly. Self-development is
     the single biggest Claude consumer, and it's 100% un-delegated.
  2. **Research/breadth fan-outs run as Claude subagents** (the `Agent`/Task tool), not Codex workers,
     even though `codex exec` web-searches and has idle quota. (Memory `delegate-heavy-work-to-codex`
     names this but nothing structural enforces it.)

## Alternatives considered
- **A. Exhortation only** (keep the memory note, "try to delegate more"): rejected — that's what we
  have, and it demonstrably didn't change behavior (#1 proves it).
- **B. Route EVERYTHING through Codex, including gate/trust code:** rejected — a Codex worker editing
  the very gates that check it is a bootstrapping/confused-deputy hazard; some code must stay
  Claude-authored.
- **C. (chosen) Delegate-first with a small, explicit Claude-only allow-list + dogfood the
  orchestrator through its own pipeline for everything else.**

## Proposed changes
1. **Dogfood: dispatch orchestrator self-development to Codex.** Treat the orchestrator repo like any
   other codebase — non-trivial changes to its own non-trust-critical code (helpers, commands, tests,
   docs, reporting) get a schema-validated spec → Codex worker → deterministic gates → **independent
   Claude reviewer** → PR → merge. The full existing trust machinery (approval, fail-closed gates, CI,
   human-only `main`) applies unchanged.
2. **Claude-only allow-list (small, explicit):** (a) the trust-critical core — gate logic, worker
   isolation, approval/autonomy, evidence integrity, reviewer, merge/branch protection; (b) the
   independent review layer (Claude reviews Codex's code — never Codex reviewing Codex's code);
   (c) final judgment/synthesis and reconciliation of dual-vendor research; (d) trivial/urgent
   one-liners where spec ceremony costs more than it saves. Everything else defaults to Codex.
   - Any spec that *touches* a trust-critical path is classified **high risk** → per-dispatch human
     approval + (per Critical tier) a SOL design review, so the dogfooding hazard is gated, not
     trusted.
3. **Research defaults to Codex.** Idea-stage / breadth fan-outs run parallel `codex exec` workers
   (web search on); Claude does reconciliation + the independent-diversity pass only. This flips the
   heavy research consumer Claude→Codex while preserving the two-vendor rule.
4. **Make it visible (feedback loop):** extend `dispatch metrics` with a delegation ratio (Codex
   worker-attempts vs. direct-Claude control-plane commits over a window) so the split is measurable
   and the regression is caught, not re-discovered from usage screenshots.
5. **Encode it in CLAUDE.md** as a first-class operating rule ("Execution split"), not a memory note,
   so it binds every session.

## Affected boundaries / consumers
- Trust boundary: a Codex worker can now propose edits to orchestrator code — bounded by scope +
  gates + independent Claude review + high-risk gating for trust-critical paths. No gate is removed.
- The independent-reviewer invariant is *strengthened* in importance (Claude must review Codex's
  orchestrator code); must never collapse to Codex-reviews-Codex.

## Failure modes / blast radius
- **A worker weakens a gate it's editing** → caught by: it can't touch trust-critical paths without
  high-risk human approval + SOL review; Claude reviewer is independent; CI + human-only `main`.
- **Misclassification** (trust-critical work routed as low-risk) → mitigate with an explicit
  path-based trust-critical list that forces high risk.
- **Over-delegation of judgment** (Claude stops thinking) → the allow-list keeps final
  judgment/synthesis + reconciliation with Claude by rule.
- **Codex quota exhaustion from the increased load** → that's the *goal* (95% idle headroom); workers
  already classify quota limits as `interrupted`, not failure.

## Ordered steps
1. SOL adversarial review of THIS plan (PASS/BLOCK). Reconcile.
2. Encode the "Execution split" rule + Claude-only allow-list in CLAUDE.md.
3. Define the trust-critical path list (forces high-risk classification).
4. Add the delegation-ratio to `dispatch metrics`.
5. Adopt research-via-Codex as the default fan-out mechanism.
6. Prove it on the NEXT orchestrator improvement (#3 reviewer diff-blindness or a helper) by
   dispatching it as a Codex spec rather than editing directly.

## Validation criteria
- The next non-trivial, non-trust-critical orchestrator change is executed by a Codex worker, not
  Claude. `dispatch metrics` shows the delegation ratio moving. Codex weekly usage rises off ~5%.

## Rollback / irreversibility
- Fully reversible: it's an operating-policy + a metrics addition + a doc rule. Revert the CLAUDE.md
  rule to fall back to Claude-direct. No data migration, no protocol change.

## Open questions (for SOL)
1. Is dogfooding the orchestrator through its own worker pipeline a net trust GAIN (more code goes
   through gates+independent review instead of un-reviewed Claude-direct edits) or a net LOSS
   (worker-authored changes to the tool that gates workers)? Where exactly should the Claude-only line
   sit?
2. Does routing orchestrator code to Codex + keeping Claude as its reviewer preserve enough
   independence, or does Claude-authored-spec + Codex-exec + Claude-review re-introduce correlated
   blind spots?
3. Any load/quota or provenance failure mode we're underweighting?
