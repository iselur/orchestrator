# Claude reconciliation — R22 gap review (vs SOL's independent assessment)

Claude's independent view, reconciled against SOL's response.md (2026-07-14).

## Where we AGREE (high confidence)

1. **Coverage matrix is accurate.** Stages 2 (decide) and 5 (plan iteration) are genuinely BUILT —
   today's PLAN-003/PLAN-004 dual-validation loops are live proof. Stage 4 (Jira/Linear) is MISSING
   — a Linear MCP connection exists in the orchestrator's session but nothing is wired to specs.
   Stages 9 (deploy) and 10 (maintain-a-product) are MISSING/PARTIAL — the dispatcher's lifecycle
   ends at merge.
2. **The single biggest risk — recursive control-plane accretion — is real**, and today's PLAN-003
   trajectory (Dispatch 0, six dispatches, CAS activation heads) is the live example. The corrective
   ordering SOL proposes (smallest truthful kernel → one thin end-to-end pilot with REAL work →
   only then more control plane) matches the audit's own action 10 and is the right default.
3. **Truth/authority cleanup list** (ledger watchlist drift, stale DECISION.md files, README safety
   overstatements) — all verified real; watchlist fixed this session; the rest stays queued in the
   baton (truth-in-docs, action 8/B).
4. **The lifecycle-spine gap** (no identifier chain from idea → … → maintenance event) is the
   correct architectural diagnosis of why stages 1/3/4/9/10 feel bolted-on.

## Where I DISAGREE or qualify

1. **"Claude's role has been narrowed below the vision" — misreading.** The operator's dictation
   explicitly assigns Claude the AI-engineering-MANAGER role and Codex the manager+executor role;
   CLAUDE.md's reservation of Claude for orchestration/judgment IS the vision, not a contradiction.
   (The vision does call both "individual contributors" — but the operative sentence is the role
   split, which the current setup matches.)
2. **"Slim Dispatch 0" vs the dual-validated PLAN-003.** SOL-as-vision-reviewer says shrink the
   bootstrap; SOL-as-security-critic (two BLOCK rounds) demanded exactly that machinery. Both
   cannot be fully honored. My position: PLAN-003 rev4's Dispatch 0 is already the scaled-minimal
   form of what the security review would PASS (each mechanism traces to a named exploit), so I
   will complete its authorization loop — but the OPERATOR should decide the strategic fork:
   (a) implement Phase 1 as authorized (≈6 dispatches, weeks of pipeline work, hardest-possible
   gate), or (b) trim to a reduced truthful-kernel subset (attestation + v4 binding + choke point;
   defer the full activation ledger/venv hardening) and spend the difference on the pilot +
   lifecycle spine. This is R12-class (keep-capacity vs lean-core) — the operator's call, not mine.
3. **Effort classes:** SOL's items 2/7/8 (lifecycle spine, deploy plane, ops loop) are L each; the
   honest sequencing consequence is that stages 9-10 are quarters away, not sprints. The vision is
   directional — the matrix should not be read as a near-term backlog in full.

## Recommended next actions (for the operator)

1. Decide the fork in disagreement 2 (full Phase 1 vs trimmed kernel). Everything else sequences
   behind it.
2. Cheap, high-value now: R22 item 4 scoped to LINEAR only (MCP already connected) — spec-to-Linear
   sync as an ordinary-lane spec after Phase 1 Dispatch 2.
3. Adopt the "one representative end-to-end pilot" (SOL item 9, audit action 10) as the acceptance
   test for the whole factory — the first REAL product idea that arrives goes through all stages
   that exist, and every gap it hits becomes the priority list.
