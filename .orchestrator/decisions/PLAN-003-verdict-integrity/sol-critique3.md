Revision 4 remains blocked by three material defects.

1. The direct-dispatch preflight has no executable enforcement mechanism.

   Sections R1.3–R1.4 and §4.3 require direct invocation of the existing repository dispatcher to stop before worktree creation, candidate launch, or reviewer invocation. But observed fact 13 says that dispatcher is currently directly callable; Dispatch 0 does not modify repository content; and Dispatch 1 may modify `scripts/dispatch.py` only for metrics extraction. Protecting authoritative evidence and PR credentials prevents authorization, but it does not make the existing dispatcher perform the claimed early preflight or prevent it from launching workers and reviewers using the operator’s existing execution and Codex access. Section 4.3 even acknowledges that direct execution may create local files.

   Minimal amendment: define a concrete Dispatch 0 enforcement step that exists before genesis—for example, an independently authorized bootstrap patch adding the mandatory preflight to every repository entry point, combined with broker-only worker/reviewer execution authority and removal of ambient credentials. Specify which operation is guaranteed to occur before worktree creation and test old, copied, Python-direct, wrapper, operator, and worker entry points. Alternatively, weaken R1.4 to prohibit only authoritative effects, but that would abandon the explicitly required pre-candidate fail-closed invariant.

2. The mutable singleton head contradicts the stated preservation of prior head records.

   Section 4.8 atomically replaces `/srv/codexwork/activations/active-head.json` on every transition. Section 9.4 simultaneously says a prior head record is never edited or deleted and that originals remain evidence. No append-only head-generation artifact or archive operation is defined. The ledger contains similar state, but the document does not declare the replaced singleton to be a non-evidentiary derived projection whose historical bytes need not survive.

   Minimal amendment: either create an immutable, no-replace head-generation record for every transition and make the singleton a replaceable pointer to it, or explicitly state that only manifests and ledger records are historical evidence and remove the requirement to preserve prior singleton-head files. Add a test proving the chosen historical representation survives activation and rollback.

3. The crash test can pass while R1.18 is unmet.

   R1.18 requires exact phase-specific outcomes: before ledger durability the old head remains selected; after ledger durability but before replacement the old head remains selected; and after durable replacement the head references the already durable transition. Section 8.2 instead accepts “one consistent selected head or fail-closed recovery.” A missing or unusable head after either pre-replacement crash could therefore make the test green merely because dispatch refuses, even though R1.18 requires continued selection of the old head. Likewise, post-rename loss may be accepted as generic fail-closed recovery.

   Minimal amendment: make each crash injection assert the precise R1.18 state after an actual service restart or filesystem remount, including exact head bytes, referenced ledger record, manifest digest, and dispatchability of the required old or new selected parent. Reserve generic fail-closed recovery only for explicitly enumerated states outside those promised crash points.

The embedded frozen approval parser/schema removes the former repository-schema circular prerequisite, assuming the independent installation authority verifies the outer frozen artifact digest. The distinct-UID/process-namespace controller boundary and fail-closed syscall-denial checks are internally sufficient for the stated producer-authentication requirement. The remaining activation ledger/CAS sequencing is broadly coherent once the head-history contradiction and crash oracle are corrected.

VERDICT: BLOCK
