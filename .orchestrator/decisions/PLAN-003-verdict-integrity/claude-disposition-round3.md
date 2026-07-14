# Claude disposition — SOL critique round 3 of PLAN-003 rev4 (BLOCK, 3 findings)

Convergence: 12 → 4 → 3; round-2 amendments 2 (embedded parser) and 4 (UID boundary) explicitly
accepted; activation machinery "broadly coherent" pending consistency fixes. All 3 SUSTAINED:

1. **Direct-dispatch preflight unenforceable pre-Dispatch-4 → SUSTAIN, take the critic's
   alternative (scaled).** R1.4 weakens to prohibit AUTHORITATIVE EFFECTS only: a direct
   `scripts/dispatch` invocation cannot write authoritative evidence roots, cannot reach the
   PR/push credential, cannot append the activation ledger, and its outputs are non-authoritative
   by §4.14 — but it MAY still locally create worktrees/launch processes until Dispatch 4 installs
   the native preflight in the repository dispatcher. Record as an explicit residual (bounded:
   wasted compute + local artifacts; no authorization path). Keep the bypass spy test asserting
   evidence roots untouched + zero PRs; drop the pre-worktree fail claim. Rationale: patching every
   entry point via a pre-genesis bootstrap patch rebuilds Dispatch 4 early — exactly the accretion
   the operator's gap review warns against; the load-bearing invariant is no-authoritative-effects.
2. **Head history contradiction → SUSTAIN.** Declare `active-head.json` a non-evidentiary derived
   POINTER (replaceable); the append-only activation ledger is the sole historical evidence;
   delete the prior-head-preservation sentence; add the survival test for ledger records across
   activation + rollback.
3. **Crash oracle too weak → SUSTAIN.** Each crash injection asserts the exact R1.18 phase state
   after restart/remount: exact head bytes, referenced ledger record, manifest digest, and
   dispatchability of the promised old/new parent. Generic fail-closed recovery permitted only for
   enumerated states outside the three promised crash points.

Rev5 changes ONLY these three items + affected tests/residuals. Everything else frozen.
