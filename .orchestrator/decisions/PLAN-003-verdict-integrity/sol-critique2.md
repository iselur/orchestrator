## Material findings

### 1. Dispatch 0 is not established as the exclusive authorization path

Dispatch 0 is independently installed and operator-authorized, so it does provide a legitimate external trust root. Its own verifier is checked by independent human review, approval-bound hashes, installation permissions, and mutation drills—not by candidate code. That part is sound.

The loop is not fully broken, however, because the old dispatcher remains callable:

- The current gate trusts the child return code ([scripts/dispatch.py](/home/val/orchestrator/scripts/dispatch.py:935)).
- Dispatch 0 “cannot silently edit tracked repository files.”
- §4.3 merely declares `bootstrapctl` the “required invocation path.”
- Native activation enforcement does not arrive until Dispatch 4 under R1.10.
- No Dispatch 0 validation attempts to invoke `scripts/dispatch` directly and prove that it cannot create authoritative evidence or open a PR.

Consequently, all Dispatch 0 tests could pass while the existing falsely-green dispatcher remains a usable parallel authorization path. That violates R1.5 and leaves the historical failure class reachable.

Minimal amendment: Dispatch 0 must install a machine-enforced choke point. Before Dispatch 1, only the root-owned launcher/service should possess the credentials and filesystem authority needed to create authoritative attempt artifacts or open PRs. Direct pre-Dispatch-4 invocation of the repository dispatcher must fail before candidate work or, at minimum, be incapable of authorization and PR creation. Add a direct-bypass test with evidence and PR spies at zero.

### 2. The approval-schema prerequisite has no defined non-self-gated provenance

The sequencing is syntactically clear—approval schema first, Dispatch 0 second—but its trust dependency is not closed.

Evidence:

- §4.1 and implementation step 1 require the separate approval-schema plan to “land and activate” before Dispatch 0.
- The current gate is explicitly known to certify exit-zero skips and incomplete testing.
- R9.8 specifies what the new schema must bind, but not how that repository change is independently validated and activated.
- “Baton action 4” is not a machine-checkable prerequisite identity, digest, activation artifact, or trust proof.

If that schema change is merged through the existing gate, it is itself authorized by the failure-prone mechanism that Dispatch 0 is supposed to replace. If it requires Dispatch 0 for safe activation, the dependency is circular.

Minimal amendment: name the exact prerequisite plan/artifact and require its activation proof to include a non-self-gated authorization path independent of PLAN-003 and the current test gate. Alternatively, embed the minimal strict approval parser/schema needed by Dispatch 0 in the independently reviewed operator-installed bootstrap artifact. Dispatch 0 must refuse unless that provenance proof and exact schema digest validate.

### 3. The activation manifests do not constitute a complete state machine

There are two missing machine states.

First, genesis is undefined. The strict manifest requires a string `previous_active_commit`, while step 6 creates the first current-parent manifest on a fresh installation where no prior activation exists. No null/sentinel form or genesis validation rule is specified.

Second, there is no authoritative current head. `/srv/codexwork/activations/<commit>.json` is an immutable collection of historical manifests. A dispatcher verifies that its own manifest is valid, but nothing requires its commit to equal a singleton currently selected activation. Therefore:

- A stale parent can continue dispatching after a successor activates.
- Two sibling commits can both obtain manifests naming the same predecessor.
- R1.9’s no-intervening-commit rule does not prevent later use of the losing or stale branch.
- Rollback prose does not define a machine transition.
- §8 has no genesis, sibling-race, stale-parent, or rollback-transition test.

All listed activation tests could pass while multiple parents remain independently “active.” This leaves R1.5, R1.9, R1.10, and the Phase 2 prerequisite unvalidatable as state invariants.

Minimal amendment:

- Define a strict genesis variant, such as `previous_active_commit: null`, bound to an approval-authorized anchor and Dispatch 0 digest.
- Add a root-owned singleton active-head mechanism—an append-only activation ledger plus atomic compare-and-swap head, or equivalent service configuration.
- Every dispatcher must verify both its immutable historical manifest and that its commit is the selected head.
- Activation and rollback must be new atomic transitions from the current head.
- Add genesis, concurrent siblings, stale-parent-after-successor, rollback, and crash-interruption tests.

### 4. Producer authentication is not fail-closed against direct process manipulation

The environment, descriptor, nonce, separate-pipe, and controller-only-event design correctly closes the stated naïve forgery channels. The gap is the process privilege boundary.

The repository convention says worker and gate-test processes run as `codex-worker`. Section 4.6 says the controller is made non-dumpable only “where supported” and mentions ptrace restrictions, but:

- It does not specify the controller’s UID/process namespace relative to candidate processes.
- It does not require failure to establish those protections to abort testing.
- R2.6 and §8.6 test environment inheritance and `/proc/.../environ`/`fd`, but not `ptrace`, `process_vm_readv/writev`, or `pidfd_getfd`.

If the controller or trusted helper shares the worker UID and non-dumpability or isolation is missing, candidate code may directly read or alter controller state or duplicate a protected descriptor. The `/proc` pathname tests can pass under mount restrictions while another same-UID process-access mechanism remains available.

Minimal amendment: explicitly place the event-producing controller outside the candidate UID/process namespace, or require the complete same-UID process-isolation setup to succeed before launching candidates. Add direct negative tests for ptrace attach, `process_vm_*`, and `pidfd_getfd`; unsupported or ineffective protection must fail closed.

## Non-blocking assessments

- Exact expected assertion sets plus exactly-once enforcement prevent partial control-flow execution from being mistaken for a complete test. Per-substantive-assertion mutation prevents unconditional success recording. They cannot prove semantic sufficiency, but §2.2 assumption 8 explicitly accepts that limitation and retains human approval; I do not reclassify it as a blocker.
- Tree revalidation leaves a real window, including transient mutation-and-restoration during testing. Commit-object review and PR inputs keep reviewed and proposed commit content aligned, but do not prove every tested byte remained equal to that commit throughout execution. This is the explicitly accepted read-only-mount residual, so it is advisory rather than blocking.
- The six-dispatch sequence is otherwise plausible on one box. Dispatch 3 can remain transitional because Dispatch 0—not the partially migrated native gate—authorizes Dispatch 4. The fresh-box path is presently incomplete only because of the prerequisite-provenance and activation-genesis defects above.
- Section 8 is extensive, but it can go green while the four material properties above remain unmet: direct-dispatch bypass, untrusted prerequisite provenance, stale/forked activation, and direct process manipulation are not tested.

I attempted to refresh the cited repository locations, but workspace command execution failed before the commands ran with `bwrap: loopback: Failed RTM_NEWADDR`. The findings above therefore rely on the supplied live repository conventions and cited implementation behavior; they do not depend on unverified symbol movement.

VERDICT: BLOCK
