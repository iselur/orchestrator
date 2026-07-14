PLAN-003 is not safe to authorize. It closes the exact “exit zero despite SKIP” symptom, but it does not establish that the trusted assertions—not candidate code—produced the attestation, that all required assertions ran, or that the tested candidate tree is the tree later reviewed. Worse, Dispatches 1–3 and Dispatch 4’s activation occur before a non-self-gating verifier exists.

The current failure is real: the gate trusts the child return code ([dispatch.py](/home/val/orchestrator/scripts/dispatch.py:935)), the wrapper maps zero to PASS ([scripts/test](/home/val/orchestrator/scripts/test:22)), and SPEC-015 contains successful prerequisite skips ([test.log](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/test.log:7), [test.log](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/test.log:10), [test.log](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/test.log:30)). PLAN-003 still permits related vacuity.

## Blocking findings

### B1. The five-dispatch sequence bootstraps through the gate known to be unsound

Dispatches 1, 2, and 3 run before Dispatch 4 introduces attestation. Dispatch 3 changes every test and the assertion helper while the installed gate still trusts aggregate exit status. Dispatch 4 then introduces its own runner, policy, helper interpretation, and activation tests as candidate content. Its post-merge “new parent tests itself” drill is still self-certification: the newly introduced policy and runner decide what their own activation must execute.

The current parent cannot enforce R1 or distinguish a candidate’s substantive tests from a vacuous `test_command`; it only sees the return code at [dispatch.py](/home/val/orchestrator/scripts/dispatch.py:935). Exact blob lists and human high-assurance review do not satisfy the stated “no candidate self-gating” invariant.

Minimal amendment: introduce a separately authorized bootstrap gate before Dispatch 1. It must be installed outside the candidate commit, contain a frozen required-test inventory and expected assertion inventory, execute candidate code through the worker boundary, and gate all five dispatches. Dispatch 4’s runner and policy must be validated by that prior bootstrap gate, not activated based only on their own tests. Alternatively, reorder the work so a minimal independently installed attestation gate is the first change.

### B2. “At least one assertion” still certifies vacuous or partially unrun tests

R1 requires only a positive assertion count. A trusted test can execute one trivial setup assertion, bypass every substantive branch, and exit zero. It then satisfies the planned aggregate even though the important test body never ran. The migration drill covers one representative per shell idiom, not every migrated assertion or every required branch.

This is the same failure class in a more structured format: “some assertion ran” replaces “some process exited zero.”

The retained free-form `test_command` is worse. R1 acceptance criterion 5 explicitly allows `test_command: true`; §4.5 requires only that this supplemental command exit zero. Thus the gate may report successful testing even when the spec-declared test executed no assertion at all.

Minimal amendment:

- Give each required test a parent-owned exact set of required assertion IDs, not merely a minimum count.
- Require every expected assertion exactly once, with no unknown or duplicate assertion.
- Mutation-test every migrated assertion or explicitly justified conditional assertion, not one representative per idiom.
- Remove free-form `test_command` from authorization evidence, or subject it to an attested parent-owned test-ID/expected-assertion contract. A `true` command must never be represented as successful test evidence.

### B3. The nonce labels events but does not authenticate their producer

The plan injects the nonce, test ID, trusted root, target root, and assertion channel into the trusted test environment. Candidate code invoked by that test normally inherits environment variables and open descriptors. A malicious candidate implementation—not merely a candidate copy of the test—can therefore emit valid events for the trusted test.

Acceptance criterion R1.8 tests the wrong adversary: a candidate test stub. It does not test candidate system-under-test code reading the nonce or writing the trusted harness’s event channel. Separate aggregate namespaces do not help if both executions can reach the same live channel or its credentials.

Nonce secrecy is especially weak when harness and candidate run as the same `codex-worker` UID. Depending on `/proc` and ptrace settings, candidate code may also inspect ancestor environments or duplicate descriptors.

Minimal amendment: specify a real assertion-producer boundary. At minimum:

- Candidate processes receive neither nonce nor assertion descriptor.
- The descriptor is closed before every candidate `exec`.
- Assertion helpers scrub all attestation variables when invoking candidate commands.
- Trusted and supplemental executions use separate pipes and per-invocation nonces.
- The trusted controller alone converts observed command outcomes into assertion events.
- Add an end-to-end attack where candidate application code tries environment, inherited-FD, `/proc/<ppid>/environ`, and `/proc/<ppid>/fd` forgery.

If same-UID isolation cannot make that robust, the trusted controller and candidate process need distinct security principals.

### B4. The tested target is not bound immutably to `worker_commit`

Recording `candidate_target_root` and `worker_commit` does not prove the worktree bytes equal that commit. Candidate code can modify its worktree during a trusted test. The supplemental `test_command` can mutate it after required tests finish. The reviewer can then receive a different diff/tree from the one tested.

The current gate already runs a child command and retains only its result ([dispatch.py](/home/val/orchestrator/scripts/dispatch.py:935)); PLAN-003 adds no explicit read-only candidate snapshot, post-command clean-tree verification, or tree digest revalidation before review and PR creation.

Minimal amendment: test an immutable candidate snapshot. Use a read-only bind of the exact committed tree plus a separate writable build/output directory. Revalidate the commit, index, tracked bytes, untracked policy, and tree identity after every candidate-controlled process and immediately before review and PR opening. Add a candidate program and supplemental test that mutate tracked and untracked inputs after emitting PASS.

### B5. §4.4 does not define a race-safe blob execution mechanism

“Execute the verified descriptor or an equivalently race-safe path” leaves the critical operation to implementer discretion. For shell scripts, verifying an open descriptor and then executing a pathname is a TOCTOU. Executing `/proc/self/fd/N` has interpreter and descriptor-lifetime complications. Directory components, sourced helpers, fixtures, policy, interpreters, and the runner itself also belong to the trust closure.

The plan records a blob hash per test but does not require a complete closure manifest or race tests. A parent checkout being associated with a commit is not proof that its working-tree files still match that commit.

Minimal amendment:

- Select one concrete mechanism: for example, a root-owned, read-only installed snapshot materialized from the exact commit, with a closure manifest for runner, policy, tests, helpers, fixtures, schema, and wrapper.
- Define component-by-component `openat2`/`O_NOFOLLOW` rules or immutable copied-blob execution.
- Never reopen a verified pathname for execution.
- Verify interpreter identity and helper/fixture blob identities.
- Add concurrent replacement, directory-symlink swap, helper swap, fixture swap, and interpreter-shadow tests.

The plan also needs a worker-readable trusted install root outside the operator’s home. The repository convention says the operator’s home is unreachable to `codex-worker`, while §4.4 assumes tests execute from the installed parent checkout. A root-owned `/srv/codexwork/installed/<commit>` snapshot or equivalent is required.

### B6. New evidence is not made immutable

Temporary-file plus `fsync` plus atomic rename provides crash consistency, not append-only evidence. A normal atomic replace can overwrite an existing result. The plan does not require `O_EXCL`/no-replace semantics, directory `fsync`, trusted ownership of the attempt directory, single-link files, or refusal to reopen a finalized attempt for writing.

R7.4 tests only that old SPEC-015 bytes remain unchanged. That does not validate immutability of new logs, aggregates, review requests, results, or resumed attempts.

Minimal amendment:

- The dispatcher, not a worker-UID runner, owns the attempt directory and final evidence files.
- Worker output crosses a pipe; candidate code never gets a writable evidence pathname.
- Create each artifact once with no-replace semantics; reject an existing destination.
- Verify regular file, owner, mode, link count, and directory ownership.
- `fsync` files and containing directories.
- Seal a terminal manifest containing hashes of all artifacts.
- Add overwrite, hardlink, symlink, rename-swap, resume-after-terminal, and concurrent-writer tests.

### B7. Supplemental namespaces are logical labels, not demonstrated isolation

The plan says supplemental events cannot overwrite or satisfy trusted results, but does not specify distinct channels, credentials, file destinations, or OS permissions. If trusted and supplemental processes share the runner UID, nonce environment, event pipe, or result directory, a malicious supplemental process can race, duplicate, or precreate results.

Likewise, “one result in the aggregate” does not prove a test was launched exactly once; a runner could launch twice and retain one result.

Minimal amendment: separate invocation pipes and nonces, strict expected source class, dispatcher-owned aggregation, and no worker-writable aggregate path. Add a side-effect counter proving exact single launch under parallel execution, plus attacks that emit trusted IDs from supplemental and candidate-application processes.

### B8. Reviewer-log “sanitization” cannot neutralize semantic prompt injection

JSON escaping and delimiter escaping prevent structural delimiter closure. They do not prevent a model from following instruction-like text encoded inside the JSON string. Therefore R5.3’s claim that instruction-like text “cannot alter fixed reviewer instructions” is not falsifiable by string-level tests.

The reviewer already receives candidate-controlled diff text at [dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1141) and [dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1188). A sanitized log adds another semantic injection channel. Fixed instructions after the evidence reduce risk but do not establish non-interference.

Minimal amendment: narrow the acceptance claim to syntactic prompt integrity. Do not claim semantic neutralization. Prefer machine-generated attestation summaries over arbitrary log text; if the tail remains, classify the reviewer as an untrusted advisory oracle and require deterministic gates for all mechanically decidable scope/test properties. Adversarial model trials may measure risk but cannot prove the invariant.

Also add a raw-log size/resource limit. Hashing an unlimited log after the process fills disk is not a safe “oversized evidence” policy.

### B9. The venv identity and poisoning model are incomplete

The environment path is addressed only by the requirements-file hash. Two boxes with different Python versions, pip/resolver versions, platform wheels, or transitive artifacts can produce different environments at the same path. The marker records Python version but the address does not; an upgrade creates a collision that the stated idempotent installer cannot resolve cleanly.

Read-only permissions prevent direct writes but not import shadowing. Running Python with the candidate directory as cwd can load candidate `yaml.py`, `jsonschema.py`, `sitecustomize.py`, or other shadow modules before the venv package. A fixed PATH and `PYTHONNOUSERSITE` do not close this.

Minimal amendment:

- Address the environment by requirements lock hash, Python ABI/platform, and installer/wheel-lock identity.
- Use hash-locked artifacts or an approved wheelhouse; verify transitive package hashes.
- Invoke trusted Python with isolated import semantics, safe cwd, scrubbed `PYTHONPATH`/Python variables, and verified module origins under the venv.
- Verify recursive ownership, ACLs, symlinks, and writability, not just top-level modes.
- Add malicious target-root shadow modules and `sitecustomize` tests.
- Add a fresh-box provisioning test and a Python-version-change/idempotence test.

The candidate-requirements rule is also contradictory: the candidate requirements are not trusted during its gate, but provisioning after merge risks making those requirements part of the environment used to validate their own activation. Define a staged dependency-upgrade bootstrap.

### B10. Required-test policy coverage is not exhaustively testable as written

The policy language is sensible, but §8 tests only selected gaps. Missing cases include mode-only changes, symlink/type changes, submodules, `.gitmodules`, delete/add rename evasion, root-level imported modules, generated configuration, untracked files, and dirty-worktree state.

Minimal amendment: define the canonical Git diff algorithm and file-state model. Property-test every changed path to produce either a nonempty parent-required set or a policy error. Include old/new rename paths, modes, object types, submodules, unknown root paths, and worktree dirt. Bind policy evaluation to the exact base and candidate trees, not a mutable checkout.

### B11. Approval requirements contradict the declared scope

R7.6 requires approvals bound to the exact dispatch, attempt, and test-content digest. The repository convention stores approvals at `.orchestrator/approvals/<digest>.json`; PLAN-003 simultaneously declares approval-binding findings a non-goal. Dispatch 4 also requires approval artifacts to enumerate old/new test blobs, but no approval schema/validator change is assigned an allowed path.

This requirement is therefore not implementable or validatable under the stated scope.

Minimal amendment: either add approval artifact schema, validation, and tests as a separately bootstrapped high-assurance dispatch, or remove attempt/test-blob binding from R7 and explicitly accept the weaker existing invariant. The current contradiction must not remain.

### B12. Verdict v4 binds shape and position, but parsing and spec provenance remain underdefined

Current validation binds only the three artifact identities ([dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1119)), while the evaluator accepts the supplied criterion subset ([dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1106)); v4 correctly addresses that gap. But two authorization ambiguities remain:

- Standard JSON parsing commonly accepts duplicate object keys, retaining the last. A file containing two `severity`, `verdict`, or binding keys can be interpreted differently by humans and machines.
- “The bound spec’s acceptance criteria” is not tied to an immutable opened spec snapshot. Rehashing a path and later reopening it leaves a spec TOCTOU similar to the test-blob issue.

Minimal amendment: reject duplicate JSON keys and nonstandard constants during parsing. Persist the exact digest-approved criteria vector in the attempt manifest before candidate work and validate against that immutable vector. Add duplicate-key and concurrent spec-replacement tests.

Legacy display compatibility also needs a complete consumer inventory. Replacing the shared schema while asserting separate display-only readers exist can go green in the new authorization tests while breaking an unenumerated historical reader.

## Operational and sequencing defects

- Phase 2 is allowed after Dispatch 2 even though Phase 1’s integrity repair is not complete. If corrected metrics are merely one prerequisite, state that; otherwise Phase 2 must wait for Dispatch 5 and its activated parent.
- Installation and activation are checklist prose, not a machine-enforced state transition. There is no defined activation manifest, command, storage location, or refusal rule when the on-box drill is missing.
- CI can remain green while on-box tests are skipped. The current workflow’s aggregate success cannot establish worker isolation; that is already demonstrated by SPEC-015’s skipped isolation test. CI should emit only a portable validation artifact, while an on-box activation artifact must be mechanically required before the parent can dispatch.
- The two-stage compatibility procedure is not generally usable. A transitional test that accepts old and new behavior becomes a weak authoritative parent test; a strict new test then needs another promotion cycle. Define the actual three-state sequence, or require the external bootstrap authorization immediately.
- A five-merge chain needs exact installed-commit checks and exclusion of intervening integration changes. “Merged and installed” must be a recorded, verified state, not an operator recollection.
- A fresh box needs a tested provisioning path for the worker UID, trusted install snapshot, locked venv, systemd properties, ACLs, and activation manifest. CI-local venv creation does not exercise that path.

## Assumption 4 is not demonstrated

A representative-per-idiom mutation drill cannot prove a suite-wide migration is mechanical. Shell semantics vary with `set -e`, pipelines, subshells, command substitution, traps, quoting, redirection, and status capture. One correctly migrated `grep` assertion says nothing about another occurrence whose status is accidentally masked.

The minimal credible migration proof is a parent-owned assertion inventory per test, exact assertion IDs, and an induced failure for every migrated substantive assertion or a specific, reviewed justification for why it cannot be independently mutated. Pre/post mapping prose alone is not a falsifiable gate.

## Acceptance tests missing from §8

These tests should fail against today’s implementation and pass only after the corresponding invariant exists:

1. A pre-Dispatch-4 candidate replaces the test wrapper/helper with an exit-zero stub; the bootstrap gate must still reject it.
2. Candidate application code forges trusted events using inherited environment, descriptors, and `/proc`.
3. A required test emits one trivial assertion while bypassing all expected substantive assertions.
4. The spec’s supplemental `test_command` is `true` or emits no assertions.
5. Candidate code changes the tested worktree after PASS and before review.
6. A parent test/helper/fixture is replaced between verification and execution.
7. The installed parent runner, policy, schema, or helper drifts from its recorded commit.
8. Trusted and supplemental executions race with the same test ID.
9. A test is launched twice but only one result is persisted.
10. An existing finalized aggregate/log/result is overwritten or replaced through symlink/hardlink/rename.
11. Activation is attempted without the prior-parent/bootstrap validation artifact.
12. CI passes while the required on-box activation artifact is absent; activation must still fail.
13. A candidate target shadows `yaml`, `jsonschema`, or `sitecustomize`.
14. Fresh-box provisioning and Python-version changes produce the correct distinct venv identity.
15. Verdict JSON contains duplicate top-level and nested keys.
16. The bound spec file is replaced between digest validation and criterion extraction.
17. Policy classification covers mode changes, symlinks, submodules, unknown root paths, untracked files, and dirty target state.
18. The full two-/three-stage compatibility sequence is exercised end to end.

## Validation paths that can falsely go green

- The SPEC-015 adapter can reject every legacy log without exercising the production dispatcher transition. The replay must enter through the real gate state machine and prove reviewer/PR spies remain untouched.
- A sanitizer unit test can prove escaped bytes while saying nothing about reviewer semantic prompt injection.
- A constructed aggregate can pass validator tests without proving the real isolated process produced it.
- Candidate-copy substitution tests do not cover candidate application-code forgery.
- `./scripts/test` can be green while lane-required on-box tests did not authorize activation.
- The post-install drill can pass because the new policy and tests selected themselves.
- Candidate-authored extraction parity fixtures can bless changed output. Baseline output hashes must be captured before candidate work and approval-bound.
- The five-spec metrics fixture does not define window-boundary behavior. A retry before the selected window or later attempt after it can be misclassified. Eligibility should be anchored—normally by terminal-spec time—and classification must consult the complete attempt history.
- Hashing SPEC-015 before and after proves that one historical directory was untouched; it does not prove append-only behavior for new attempts.

## Overall assessment

Parent-blob verification, positional criterion binding, and structured blocker severities are good components. They authenticate inputs and eliminate several ambiguous representations. They do not, as designed, authenticate the live assertion producer, require the complete assertion set, freeze the candidate target, or provide a non-self-gating bootstrap. Those are control-plane defects, not implementation details.

Repository-access note: local shell execution was blocked before command execution by the environment’s `bwrap: loopback: Failed RTM_NEWADDR` error. The repository citations above are therefore the exact live path/line locations supplied in PLAN-003’s evidence section; the blocking design defects follow independently from the proposed protocol and sequencing.

VERDICT: BLOCK
