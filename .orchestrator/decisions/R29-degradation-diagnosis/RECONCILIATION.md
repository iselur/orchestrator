# R29 — Reconciliation of the two independent diagnoses

Two auditors, zero shared context, zero orchestrator pre-digestion (raw complaint + raw evidence
only): a fresh-context Fable agent (filesystem access, own sampling of transcripts/repo/git) and
Codex gpt-5.6-sol (mechanically extracted full dialogue + git history + repo shape, inlined).

## Where they AGREE (high confidence)

1. **The degradation was REAL, not perceptual** — but it was not "the model got dumber."
   Both cite the same objective markers: completion claimed before verification (SPEC-015 false
   PASS, "done" T1 that wasn't, stale PR status, orphaned measurement work), prose/jargon growth
   (Fable measured: jargon density x8, mean message length +58%; Codex: 9.5:1 governance-to-code).
2. **Primary cause: the external finish line disappeared.** Day 1 executed SETUP-BRIEF — a spec
   Val had already put through TWO adversarial review rounds, with gates and deterministic
   acceptance. After it, work became open-ended and self-referential (the factory improving the
   factory), where there is no ground truth to be sharp against. "The magic wasn't lost; the
   well-specified, externally checkable goal was" (Fable). "The mistake was improving the platform
   without a fixed external score" (Codex).
3. **Co-primary: process accretion became the output.** Every frustration became a standing rule;
   planning weight stopped scaling with risk (PLAN-003: 10 BLOCK rounds vs a ~50-line fix).
   Both note the operator co-authored this (NO SLIPPAGE, plan-for-everything) and both say the
   agent should have bounded it instead of literalizing it.
4. **Verification narration outran evidence** — the clearest objective failure class; the T1/T2
   fixes address the automated layer, and "claim only after verify" addresses the interactive one.
5. **Both endorse the same recovery:** one adversarially-reviewed brief per PROGRAM (not per task),
   a single active execution stream / WIP cap, review recursion capped (~2 rounds), the exogenous
   benchmark as the score, and mechanically terse communication.

## Where they DIFFER

- **Model flip-flopping:** Fable found concrete evidence (6+ unrequested fable↔opus switches after
  the Jul 13 default change; operator noticed live at 20:27) and rates it CONTRIBUTING; Codex rates
  it weak/unproven. Reconciled: real phenomenon, secondary magnitude — pin the model, don't treat
  it as the diagnosis.
- **Operator input quality:** Fable names it directly (voice-note dictation, mangled names, no
  done-criteria); Codex folds it into "the interaction jointly reinforced over-expansion."
  Reconciled: it matters at the margin — typed intent + one checkable done-criterion per request
  is cheap and high-leverage.
- **Context saturation/compaction:** Codex ranks it #4 (amplifier, not cause); Fable notes it under
  model/config instability. Agreed: prefer fresh sessions per workstream over 10h marathons.

## Adopted (operator-facing summary delivered 2026-07-14)

- Next program gets ONE brief with gates + deterministic acceptance (the SETUP-BRIEF shape), run
  end-to-end; arbitration only at gates.
- WIP limit: one active execution stream; new ideas → backlog, not new threads.
- Review recursion cap: draft → one adversarial review → one revision → ship or escalate.
- Exogenous benchmark (R28) is the score that replaces the missing finish line.
- Communication: Outcome / Verified / Not done / Risk / Next — five bullets, no new coined terms
  unless they name implemented code.
- Model pinned; fresh session per workstream.
- Operator-side asks recorded: typed one-line intent + explicit done-criterion; no more
  audits-of-audits.
