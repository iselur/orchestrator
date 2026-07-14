# Claude disposition — SOL round 4 of PLAN-003 rev5 (BLOCK, 4 findings)

Convergence: 12 → 4 → 3 → 4 (narrower each round; assertion model, privilege boundary, metrics
semantics, and ledger/head model now explicitly hold). All SUSTAINED with chosen semantics:

1. **Direct-run commit promotion (R1.4 unvalidatable) → SUSTAIN; choose semantic (a).** A commit
   produced by a direct invocation may be readmitted ONLY as untrusted input to a new
   service-controlled attempt: fresh attempt identity, fresh tests, fresh review, fresh evidence,
   service-controlled push/ref; NO local evidence, review output, attestation, or test result is
   ever adopted. Rewrite R1.4 to prohibit ADOPTION OF ARTIFACTS (evidence/review/attestation/PR),
   not the existence of the commit. Add the regression: direct-invocation commit + local evidence →
   later admission → assert fresh evidence generated, local artifacts ignored, push/PR only via
   broker.
2. **Dispatch 5 has no trusted oracle → SUSTAIN.** Extend the frozen bootstrap verifier with a
   **Dispatch 5 profile** (simplest of the two options: Dispatch 0 already owns frozen profiles;
   adding one is smaller than making Dispatch 4 ship v4 test content it cannot yet validate). Every
   §8.7 case maps to a Dispatch-0-owned assertion inventory. R10.4 (Phase 2 unblock) additionally
   requires the Dispatch 5 profile to have passed.
3. **transition_id circularity → SUSTAIN.** Define `transition_id` BEFORE manifest creation over an
   explicitly enumerated preimage that EXCLUDES `transition_id` and `target_manifest_digest`
   (prev_active_commit, target_commit, verifier_digest, approval_digest, timestamp, nonce). A
   manifest's ID identifies its CREATION transition; the head's ID identifies the CURRENT selecting
   ledger record; rollback binds via `ledger.target_manifest_digest == hash(manifest)` — never ID
   equality.
4. **Crash durability oracle → SUSTAIN, scaled.** Specify the exact fsync ordering (stage+fsync
   ledger record → atomic no-replace publish → fsync ledger dir → "ledger durable"; fsync temp head
   → rename → fsync dir → "head durable"); move the third promised crash point after the final
   barrier; enumerate rename-before-dirfsync as its own partial state. SCALE the oracle: the plan
   asserts **process-crash consistency** (SIGKILL between barriers, verified by strace-observed
   syscall ordering), NOT durable power-loss consistency — a faulting-filesystem/power-loss harness
   is out of scope and recorded as a residual. This keeps the requirement validatable with the
   tests we can actually run on this box.
