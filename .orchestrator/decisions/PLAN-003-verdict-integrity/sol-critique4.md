PLAN-003 revision 5 remains blocked by four material defects.

### 1. Direct-run source output can still be promoted through a fresh authoritative attempt

R1.4, §§4.3 and 4.14 categorically say outputs from a direct repository invocation cannot be imported, promoted, or used to obtain a PR. The enforced boundary protects evidence, ledger, head, and credentials, but does not track the provenance of Git commits or refs.

A direct invocation can create a worker commit. A later `bootstrapctl` attempt can accept that same commit as candidate input, generate fresh authoritative evidence, and have the broker push it and open a PR. Nothing binds candidate-commit creation to the service-issued launch capability or distinguishes that commit from any other candidate commit.

This does not necessarily reintroduce forged evidence—the fresh run may be safe—but it makes R1.4’s absolute prohibition unvalidatable and leaves the requested “PR from its worktree” case undefined.

Minimal amendment: explicitly choose one semantic:

- Permit the commit to be readmitted solely as untrusted input to a new service-controlled attempt, requiring fresh tests, review, evidence, attempt identity, and a service-controlled push/ref; clarify that no local evidence or review output is adopted.
- Or, if all promotion is forbidden, add service-owned candidate refs/worktrees and enforce candidate provenance from the launch capability.

Add a regression that creates a commit and local evidence through direct invocation, then attempts later admission and verifies the selected rule.

### 2. Dispatch 5 lacks an authoritative oracle for its own requirements

Dispatch 0 freezes profiles only for Dispatches 1–4 (§4.1). Dispatch 5 adds or modifies its v4-specific tests (§4.2, steps 37–41), while R2.13 and R2.17 correctly classify candidate-modified tests as supplemental and unable to satisfy trusted required results.

Consequently, every §8.7 test can report green as candidate-controlled supplemental output while R4 or R5 remains unmet. The document does not identify any Dispatch-4-parent-owned test content or exact assertion inventory covering those v4 cases before Dispatch 5 activates. Phase 2 can then unblock under R10.4 even though the new authorization gate was never independently tested against its stated requirements.

Minimal amendment: install the complete Dispatch 5 oracle and exact assertion inventory as trusted Dispatch 4 parent content, with that oracle itself validated by Dispatch 0’s Dispatch 4 profile. Alternatively, extend the frozen bootstrap verifier with a Dispatch 5 profile. Map every §8.7 case to those parent-owned assertions.

### 3. The manifest/ledger transition identity is circular and ambiguous

R1.8 and the §4.8 manifest embed `transition_id` as an “activation transition digest.” The ledger record then binds both that transition ID and the target manifest digest. The manifest digest therefore depends on the transition ID, while the transition digest can depend on the manifest digest. No canonical non-circular digest preimage is defined.

Rollback and reselection add another ambiguity: the immutable target manifest contains its original activation transition ID, while the current head must reference the newer rollback or reselection transition. “Mutually consistent” validation does not state which identities must equal.

Minimal amendment: define `transition_id` independently before manifest creation—for example, as a random identifier or a digest over an explicitly enumerated preimage that excludes both `transition_id` and `target_manifest_digest`. State that a manifest’s ID identifies its initial creation transition, while the head’s ID identifies the current selecting ledger record; rollback validation binds them through `ledger.target_manifest_digest == hash(manifest)`, not ID equality.

### 4. The crash protocol and its tests do not support the promised durability oracles

R1.18 promises the new head after a crash “after atomic head replacement.” But §4.8 performs the atomic replacement at step 7 and only durably records the containing directory at step 8. A crash between those operations cannot promise that the new directory entry survives recovery. The temporary head’s contents also are not explicitly fsynced before rename.

The first oracle has a related gap: a crash while creating the final ledger record may leave a visible partial record. R1.7 says malformed ledger state causes refusal, while R1.18 promises the prior parent remains dispatchable.

Finally, §8.2 permits an ordinary service restart or clean filesystem remount as the durability test. Neither simulates loss of non-durable writes; a clean unmount normally flushes them. Those tests can pass even if the required fsync ordering is absent.

Minimal amendment:

- Stage and fsync each ledger record, publish it atomically with no-replace semantics, and fsync the ledger directory before declaring “ledger durable.”
- Fsync the new head file, rename it, and fsync the containing directory before declaring “head replacement durable.”
- Move the third promised crash point after that final durability barrier; enumerate rename-before-directory-fsync as a separate partial state.
- Validate syscall ordering plus recovery using a power-loss/faulting-filesystem harness, or narrow the requirement explicitly to process-crash consistency rather than durable crash consistency.

The exact assertion model, controller/worker privilege boundary, metrics semantics, and the append-only-ledger/derived-head distinction otherwise hold together on the document’s stated assumptions.

VERDICT: BLOCK
