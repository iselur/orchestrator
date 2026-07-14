---
id: PLAN-003
created: 2026-07-14T05:42:58Z
author_model: gpt-5.6-sol
status: challenged
task: "PHASE-1 PLAN — trimmed truthful kernel for verdict integrity and metrics semantics"
ledger_ref: R24
lane: mixed
supersedes: drafts/verdict-integrity/PLAN-001
revision: 7
---

# PLAN-003 — Phase 1 trimmed truthful kernel

## 1. Decision & non-goals

Phase 1 will ship the smallest end-to-end mechanism that prevents the orchestrator from certifying unrun, skipped, vacuous, or forged tests.

The kernel has three deliveries:

1. An operator-installed, root-owned authorization choke point, installation record, trusted parent snapshot, and minimally provisioned gate environment.
2. Behavior-preserving extraction of metrics into `scripts/metrics_report.py`, followed by the corrected metrics semantics.
3. Parent-owned test attestation, producer-authenticated assertion events, parent-content required tests, candidate-tree revalidation, verdict schema v4, structured blockers, and the real SPEC-015 replay.

The root-owned launcher/service is the only path to authoritative evidence roots and the PR/push credential. A direct repository dispatcher run may perform local, non-authoritative work, but none of its evidence, reviews, attestations, test results, attempt identity, push results, or PR results can be adopted. A commit produced by such a run may be submitted only as untrusted input to a fresh service-controlled attempt.

The operator installs an exact parent commit and records its commit, tree, trusted-component digests, required-test inventory digest, verdict-schema digest, and gate-environment identity. Each authoritative attempt records that installation-record digest. Before candidate launch, the dispatcher verifies that its measured installed parent matches the recorded installation. This is deliberately a simple installed-parent check, not an activation ledger or compare-and-swap state machine.

Every required test is selected by the installed parent. Its required-test ID, exact expected assertion-ID set, test blob, helpers, and fixtures come from Git-blob-verified parent content. The required test executes against the candidate as a separate target root. Candidate-modified tests are supplemental and can never satisfy a parent-required ID during their own attempt.

Assertion events are producer-authenticated operationally:

- the controller runs outside the candidate UID and process namespace;
- candidate processes receive neither trusted nonces nor assertion descriptors;
- attestation and Python environment variables are scrubbed before every candidate `exec`;
- all non-whitelisted file descriptors are closed before every candidate `exec`;
- trusted and supplemental invocations have separate pipes, nonces, and controller state;
- only the controller converts observed outcomes into assertion events; and
- candidate access through `ptrace`, `process_vm_readv`, `process_vm_writev`, and `pidfd_getfd` is denied and tested.

Authorization requires exact assertion-set equality. A skip, missing required test, zero-assertion test, missing assertion, duplicate assertion, unknown assertion, malformed event, stale nonce, wrong source binding, nonzero result, inconsistent aggregate, or forged event becomes `failed_test` before the reviewer is invoked. Aggregate exit zero is never sufficient.

Verdict schema v4 binds exactly one ordered criteria entry to each digest-approved acceptance criterion persisted at launch. Strict JSON parsing rejects duplicate keys and nonstandard constants. Structured `advisory|blocker` finding arrays are evaluated by a mechanical blocker predicate that fails closed even when `evaluate_binary_review()` is called without prior schema validation.

The candidate tree must equal `worker_commit` after tests, immediately before review, and immediately before PR creation.

Metrics extraction remains behavior-preserving before semantics change. The corrected report uses `not_attributed_to_orchestrator`, calculates straight-through rate per completed spec rather than per attempt, consults complete attempt history, and emits JSON `null` and display `N/A` when the denominator is zero.

The reviewer receives the trusted machine attestation summary. Raw logs remain retained evidence but are not injected into the reviewer prompt in this plan.

A candidate that changes a required trust test cannot promote that test during its own attempt. Later installation of the changed test requires explicit human authorization naming both the old and new Git blob IDs.

Non-goals:

- Do not build the revision-6 activation ledger, singleton active head, CAS transition protocol, genesis form, rollback protocol, or crash-phase durability oracle.
- Do not build per-dispatch frozen bootstrap profiles or a frozen Dispatch 5 verifier.
- Do not claim that the new gate’s tests were certified by a prior frozen verifier. Each trust-critical diff is independently reviewed by humans.
- Do not build a content-addressed or ABI/platform-addressed venv ladder, wheelhouse, or dependency supply-chain proof.
- Do not inject a sanitized raw-log tail into reviewer prompts.
- Do not implement the full evidence-sealing and comprehensive `O_EXCL` suite assigned to the evidence-hashing plan.
- Do not implement the revision-6 three-stage compatibility-promotion protocol.
- Do not allow a candidate test, helper, policy, inventory, controller, schema, or dispatcher change to authorize itself.
- Do not expose the operator’s home, credentials, or private environment to `codex-worker`.
- Do not install candidate requirements before merge or permit candidate network access.
- Do not alter `.orchestrator/attempts/SPEC-015/1/*`.
- Do not retroactively authorize legacy verdicts, logs, tests, or attempts.
- Do not treat CI, `./scripts/test`, aggregate exit zero, free-form `test_command` output, or reviewer prose as independent proof that required assertions ran.
- Do not unblock Phase 2 after metrics alone. The entire trimmed kernel must be installed and validated.

## 2. Current-state evidence

### 2.1 Observed facts

1. The current test gate records `test.log` and trusts the child return code; it does not prove which required tests or assertions executed ([scripts/dispatch.py](/home/val/orchestrator/scripts/dispatch.py:935)).

2. The repository wrapper maps child exit zero to `PASS` and has no independently authorized successful-skip state ([scripts/test](/home/val/orchestrator/scripts/test:22)).

3. SPEC-015 demonstrates the false-green failure:

   - `dispatch_gate4.sh` skipped because PyYAML/jsonschema were absent ([test.log](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/test.log:7)).
   - `dispatch_parallel.sh` skipped for the same reason ([test.log](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/test.log:10)).
   - `worker_isolation.sh` skipped because on-box prerequisites were absent ([test.log](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/test.log:30)).

4. The reviewer received an aggregate exit-zero statement rather than machine evidence identifying the omitted required tests ([scripts/dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1186); [scripts/dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1188)).

5. Current verdict evaluation examines only supplied criterion entries and can accept a supplied all-`MET` subset ([scripts/dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1106)).

6. Existing review bindings cover `spec_digest`, `base_sha`, and `worker_commit`, but not an immutable launch-time acceptance-criteria vector ([scripts/dispatch.py](/home/val/orchestrator/scripts/dispatch.py:1119)).

7. A nonce does not authenticate an event producer when candidate processes can inherit the nonce, event descriptor, or access to the controller process.

8. The repository dispatcher remains directly callable, so launcher preference alone cannot make its artifacts authoritative.

9. Candidate-modified trust tests are supplemental during their own attempt and cannot independently validate their promotion.

10. Required tests currently skip when PyYAML/jsonschema are unavailable. The gate therefore needs a minimally provisioned parent-owned environment that treats missing dependencies as failure, not skip.

### 2.2 Assumptions

1. The operator can install root-owned files below `/srv/codexwork/launcher`, `/srv/codexwork/installed`, `/srv/codexwork/venvs/gate`, and the authoritative evidence and credential-service locations.

2. The root-owned launcher can invoke candidate targets through the existing `codex-worker` isolation boundary while keeping the controller outside the candidate UID and process namespace.

3. Every candidate process used by a required trust test can be launched through the parent-owned execution helper. A test that launches candidate code outside that helper is ineligible to authorize a candidate.

4. Git objects for the installed parent and candidate remain available for blob verification and tree comparison.

5. The operator can independently review every trust-critical diff and explicitly authorize old/new blob transitions for required trust tests.

6. Historical raw evidence may be absent from a clean CI checkout. The real SPEC-015 replay is therefore an on-box validation; tracked fixtures are portable companions only.

7. Machines can prove assertion execution, provenance, and binding, but cannot prove that the assertions are semantically sufficient. Human review remains responsible for test meaning.

8. The minimum gate environment uses the trusted parent’s pinned `scripts/requirements.txt`. Full transitive artifact locking remains deferred.

9. Any drift in cited symbols before authorization requires citation refresh and renewed challenge.

## 3. Requirements & acceptance criteria

### R1. Authoritative launcher, installed-parent record, and credential/evidence choke point

The root-owned launcher/service must be the exclusive path to authoritative evidence and PR/push authority. It must install and bind an exact parent without implementing the deferred activation state machine.

Acceptance criteria:

1. **R1.1:** The operator installs an exact parent commit under `/srv/codexwork/installed/<commit>` from Git objects, not from mutable candidate worktree bytes.

2. **R1.2:** A root-owned installation record binds at least:

   - parent commit and tree ID;
   - installed dispatcher/controller/runner digests;
   - required-test inventory digest;
   - required test/helper/fixture blob IDs;
   - verdict-schema digest;
   - minimum gate-environment record and requirements digest; and
   - operator authorization identity or artifact digest.

3. **R1.3:** Before attempt creation or candidate launch, the dispatcher measures its installed parent and rejects unless its commit, tree, trusted-component digests, inventory digest, schema digest, and environment identity match the installation record selected by the launcher.

4. **R1.4:** Every authoritative attempt manifest records the exact installation-record digest and measured parent commit/tree. A mismatch produces refusal before candidate work.

5. **R1.5:** Authoritative evidence roots and the PR/push credential are reachable only through the root-owned launcher/service. Repository dispatchers, candidate processes, `codex-worker`, and ordinary direct shell invocations have no independent authority to write authoritative artifacts, push, or create a PR.

6. **R1.6:** Direct invocation of repository `scripts/dispatch` leaves authoritative evidence untouched and push/PR spies at zero. Local worktrees, processes, files, reviews, and commits created by that invocation are explicitly non-authoritative.

7. **R1.7:** No evidence, review output, attestation, test result, attempt identity, push result, PR result, pathname, or digest from a direct run can be copied, linked, imported, or adopted by an authoritative attempt.

8. **R1.8:** A direct-run commit may be readmitted only as untrusted candidate input to a fresh launcher-controlled attempt with a fresh identity, fresh authoritative evidence, fresh trusted tests, fresh review, and broker-controlled push/ref and PR operations.

9. **R1.9:** The worker and candidate cannot write the installation record, installed parent content, required-test inventory, authoritative evidence directories, or credential store.

10. **R1.10:** A candidate change to a required trust test or its trusted helper/fixture requires explicit human authorization naming the exact old and new Git blob IDs before the new blob can appear in a later installed-parent inventory.

11. **R1.11:** The new blob remains supplemental during the candidate attempt that introduces it. It becomes authoritative only after merge, independent human review, explicit old/new-blob authorization, operator installation, and installation-record verification.

### R2. Exact required-test and producer-authenticated assertion attestation

Every required test must have a parent-owned ID and exact expected assertion-ID set. Only the trusted controller may produce accepted assertion events.

Acceptance criteria:

1. **R2.1:** Parent policy selects every required test ID and exact expected assertion-ID set before candidate execution.

2. **R2.2:** Each required test is launched exactly once from parent content and has exactly one final trusted invocation record.

3. **R2.3:** Authorization requires exact set equality between expected and observed assertion IDs, with each expected ID appearing exactly once.

4. **R2.4:** A missing, unknown, or duplicate assertion ID fails closed. Counts alone are never sufficient.

5. **R2.5:** A required test with an empty expected set, no emitted assertions, one trivial assertion that omits substantive expected IDs, or an aggregate exit code without invocation records yields `failed_test`.

6. **R2.6:** A required skip, diagnostic exit `77`, missing test, malformed event, stale nonce, wrong test binding, wrong source class, nonzero exit, inconsistent overall result, or missing aggregate yields `failed_test`.

7. **R2.7:** Every R2 failure occurs before reviewer invocation and leaves reviewer and PR spies at zero.

8. **R2.8:** The event-producing controller runs under a UID distinct from `codex-worker` and outside the candidate service/process namespace. Missing or ineffective separation aborts before candidate launch.

9. **R2.9:** Candidate processes receive neither trusted invocation nonces nor trusted assertion/event pipe descriptors.

10. **R2.10:** Before every candidate `exec`, the parent helper:

    - builds an allowlisted environment;
    - removes attestation variables and secrets;
    - scrubs `PYTHONPATH`, `PYTHONHOME`, `PYTHONSTARTUP`, user-site controls, and related variables; and
    - closes every descriptor except explicitly allowed stdin/stdout/stderr and command-specific data descriptors.

11. **R2.11:** Trusted and supplemental invocations use distinct pipes, per-invocation nonces, source-class bindings, and controller state. Identical test or assertion IDs cannot cross from supplemental to trusted state.

12. **R2.12:** The controller alone converts observed command outcomes into assertion events. Candidate-written JSON, text, environment values, pipe data, or aggregate files are never admitted as trusted events.

13. **R2.13:** A candidate process cannot read, alter, duplicate, or emit an accepted trusted event through inherited environment, inherited descriptors, `/proc/<ppid>/environ`, `/proc/<ppid>/fd`, `ptrace`, `process_vm_readv`, `process_vm_writev`, or `pidfd_getfd`.

14. **R2.14:** Inability to verify effective denial of the direct process-access mechanisms in R2.13 fails before the affected candidate command. There is no best-effort authorization fallback.

15. **R2.15:** A side-effect counter proves each required test launched once, including parallel execution. Double launch followed by retention of only one result fails.

16. **R2.16:** `test_command: true`, free-form output, and exit-zero commands without parent-owned assertions are supplemental diagnostic output only.

17. **R2.17:** Candidate-added or candidate-modified tests run only as supplemental tests and cannot satisfy required IDs, even if they print trusted IDs or copied nonce-shaped values.

18. **R2.18:** The attestation summary records parent commit/tree, inventory digest, required test IDs, expected and observed assertion sets, launch counts, source class, invocation bindings, controller/candidate identities, process-access-denial results, candidate tree ID, exit status, and final status.

19. **R2.19:** A constructed aggregate without controller-owned invocation records from the real isolated processes cannot authorize an attempt.

20. **R2.20:** Each substantive TRUST assertion has a mutation drill that forces its condition false and proves the matching assertion reports `ok: false` and a nonzero test result.

21. **R2.21:** Every trust-class test and attestation mechanism has a positive control proving that the unmutated fixture reaches the intended assertion and can pass. A negative test that passes only because setup failed is invalid.

22. **R2.22:** Representative-per-idiom mutation coverage may supplement non-TRUST tests but cannot replace per-substantive-assertion TRUST mutation coverage.

### R3. Parent-content required tests and candidate-tree binding

Required tests must execute from Git-blob-verified parent content against the candidate as a distinct target root. Candidate content cannot replace the trusted source.

Acceptance criteria:

1. **R3.1:** Each required test ID maps to the exact parent commit, Git path, Git mode, Git blob ID, and exact expected assertion-ID set.

2. **R3.2:** Required test scripts, trusted helpers, fixtures, controller code, inventory, and verdict schema are materialized into the root-owned installed parent and verified against their recorded Git blobs before use.

3. **R3.3:** Required tests execute from the installed parent test root and receive the candidate checkout only as an explicit target root. The candidate root is never used as the trusted test source or trusted Python working directory.

4. **R3.4:** Candidate-modified copies of required tests, helpers, and fixtures run only in the supplemental namespace.

5. **R3.5:** A supplemental test cannot satisfy or replace a missing parent-required test, even when its path and test ID match the parent test.

6. **R3.6:** The candidate worktree is revalidated after all trusted and supplemental execution. A mismatch yields `failed_test`.

7. **R3.7:** Immediately before reviewer invocation, the worktree must still have the expected `HEAD`, exact `worker_commit` tree, clean tracked/index state, and no forbidden untracked control-plane content. A mismatch yields `failed_review` and no reviewer call.

8. **R3.8:** Immediately before PR creation, the same checks are repeated. A mismatch yields `failed_review` and no PR call.

9. **R3.9:** Review diff construction and PR identity use the bound base and candidate Git commit objects, not mutable worktree bytes.

10. **R3.10:** A candidate process that mutates tracked or forbidden untracked content after emitting a successful command result cannot reach review or PR creation.

11. **R3.11:** Test selection for changes to the installed dispatcher, controller, runner, required-test inventory, required trust tests, verdict schema, and credential/evidence boundary is determined by parent policy. Candidate policy changes cannot affect their own attempt.

### R4. Verdict schema v4 and immutable criterion binding

Verdict authorization must use strict JSON and bind exactly one ordered verdict entry to every digest-approved acceptance criterion persisted at attempt launch.

Acceptance criteria:

1. **R4.1:** Before candidate work, the launcher validates the approved spec once and persists its exact ordered acceptance-criteria vector, normalized vector, indices, and vector digest in the authoritative attempt manifest.

2. **R4.2:** Review authorization never rereads a mutable spec pathname. Concurrent replacement of the spec path cannot change the persisted vector.

3. **R4.3:** Strict JSON parsing rejects duplicate keys at every nesting level, including duplicated verdict, binding, criterion, `criterion_index`, `result`, finding, or `severity` fields.

4. **R4.4:** Strict parsing rejects `NaN`, positive or negative infinity, and all other nonstandard JSON constants.

5. **R4.5:** For an N-criterion vector, only exactly N verdict entries in exact positional order with sequential one-based `criterion_index` values can be eligible.

6. **R4.6:** Missing, extra, duplicated, reordered, out-of-range, or invented criteria reject before binary evaluation.

7. **R4.7:** Each criterion entry contains the exact normalized criterion text bound to its position.

8. **R4.8:** Normalization is exactly:

   1. Unicode NFKC;
   2. CRLF and CR converted to LF;
   3. leading and trailing Unicode whitespace removed; and
   4. each remaining maximal Unicode-whitespace run replaced by one ASCII space.

9. **R4.9:** Case, punctuation, Markdown, wording, clause order, or semantic similarity do not normalize away and therefore reject when changed.

10. **R4.10:** Wrong `spec_digest`, `base_sha`, `worker_commit`, acceptance-criteria-vector digest, installed-parent commit, or installation-record digest rejects.

11. **R4.11:** v1–v3 verdicts may remain displayable through inventoried legacy readers but cannot authorize a new or resumed decision.

12. **R4.12:** The top-level verdict, criterion entries, binding object, and finding objects reject undeclared properties.

### R5. Structured findings and defensive blocker evaluation

Verdict schema v4 must represent scope, regression, and security findings as structured arrays whose entries have exact `advisory|blocker` severity.

Acceptance criteria:

1. **R5.1:** The finding domains are explicit arrays. An empty array is the only representation of no findings.

2. **R5.2:** Each finding is a strict object with required fields and a severity exactly equal to `advisory` or `blocker`.

3. **R5.3:** Unknown, null, empty, numeric, inferred, or misspelled severity values reject.

4. **R5.4:** Any blocker in any finding domain mechanically rejects an otherwise all-`MET` PASS.

5. **R5.5:** Empty arrays and advisory-only arrays remain eligible when every other binding passes.

6. **R5.6:** `evaluate_binary_review()` independently applies this predicate even when called directly without prior schema validation:

```text
blocking =
    findings is not an array
    OR any entry is not an object
    OR any required field is absent or invalid
    OR any undeclared field is present
    OR severity is not exactly "advisory" or "blocker"
    OR any severity is exactly "blocker"
```

7. **R5.7:** Malformed findings fail closed rather than raising into an implicit pass path.

8. **R5.8:** Every rejected review leaves the PR-opening spy at zero calls.

### R6. Metrics extraction and corrected semantics

Metrics extraction must preserve installed-parent behavior before the semantic correction is applied.

Acceptance criteria:

1. **R6.1:** Before extraction work, the operator captures baseline text, JSON, ordering, defaults, errors, and exit statuses from the installed parent.

2. **R6.2:** Candidate-authored fixtures cannot replace or bless the operator-captured baseline.

3. **R6.3:** The extraction checkpoint moves implementation into `scripts/metrics_report.py` while matching the captured baseline byte-for-byte or field-for-field, except for explicitly enumerated module-origin metadata.

4. **R6.4:** Existing entry points retain a lazy alias. Representative non-metrics commands do not import or depend on `scripts/metrics_report.py`.

5. **R6.5:** After parity is established, unmatched-merge labels become exactly `not_attributed_to_orchestrator`; actor identity is reported as unknown.

6. **R6.6:** The denominator is distinct eligible completed specs, not attempts.

7. **R6.7:** The numerator is specs whose first and only attempt reached normal `merged` after all applicable gates.

8. **R6.8:** Eligibility is anchored by the canonical final spec terminal timestamp in the selected half-open window `[start, end)`.

9. **R6.9:** Classification consults the complete retained attempt history, including attempts before the window and later attempts that change the canonical final result.

10. **R6.10:** A pre-window retry prevents straight-through classification. A later final attempt moves the terminal anchor to that later completion.

11. **R6.11:** The five-spec fixture yields numerator `1`, denominator `3`, rate `1/3`, excluded-in-progress `1`, and malformed/incomplete `1`.

12. **R6.12:** Zero denominator produces JSON `null` and display `N/A`.

13. **R6.13:** The semantic correction does not change dispatcher authorization, attestation, evidence, credential, review, or PR paths.

### R7. Minimum executable gate environment

The required tests must execute rather than skip because trusted dependencies are absent.

Acceptance criteria:

1. **R7.1:** The operator provisions a root-owned gate environment containing the pinned dependencies needed by parent-required tests, including PyYAML and jsonschema.

2. **R7.2:** The environment record binds the trusted `scripts/requirements.txt` digest, interpreter path/version, installed package versions, and verified origins for `yaml` and `jsonschema`.

3. **R7.3:** Trusted Python runs from a fixed safe working directory outside the candidate tree, with candidate-controlled Python environment variables scrubbed and no candidate-root import path.

4. **R7.4:** `yaml` and `jsonschema` imports must resolve beneath the configured root-owned gate environment.

5. **R7.5:** Missing, unusable, candidate-writable, or wrong-origin dependencies fail before required-test execution and reviewer invocation. They never produce SKIP or successful zero assertions.

6. **R7.6:** Candidate `yaml.py`, `jsonschema.py`, `sitecustomize.py`, or `usercustomize.py` cannot load into the trusted controller or parent test process.

7. **R7.7:** Candidate requirements are not installed during candidate validation.

8. **R7.8:** This requirement does not create a content-addressed venv, ABI/platform digest ladder, wheelhouse, or fresh-box provisioning oracle.

### R8. End-to-end false-pass regression and Phase 2 release

Acceptance criteria:

1. **R8.1:** The real SPEC-015 attempt is replayed through the production gate state machine, not through a fixture-only adapter.

2. **R8.2:** The replay detects the missing attestation and produces `failed_test` with reason `legacy_missing_attestation`.

3. **R8.3:** The SPEC-015 replay leaves reviewer and PR spies at zero.

4. **R8.4:** Existing SPEC-015 bytes remain unchanged.

5. **R8.5:** Every trust-class negative test has a positive control and every substantive TRUST assertion has its mutation drill.

6. **R8.6:** An aggregate fabricated without real controller-owned isolated invocation records cannot authorize the replay or a synthetic attempt.

7. **R8.7:** Phase 2 remains blocked until all three PLAN-003 dispatches are merged where applicable, independently reviewed, operator-installed, installation-record verified, and validated through the required on-box checks.

## 4. Design / approach

### 4.1 Dispatch decomposition and dependency order

| Order | Dispatch | Lane | Purpose |
|---:|---|---|---|
| 0 | Root-owned launcher, installation record, authoritative evidence/credential boundary, parent snapshot, and minimum gate environment | operator-installed trust foundation | Establish the choke point; install and record the exact current parent; provision dependencies needed to execute required tests; prove direct repository runs are non-authoritative. |
| 1 | Metrics extraction and semantics | extraction checkpoint high-assurance; semantic checkpoint ordinary | First prove behavior-preserving extraction into `scripts/metrics_report.py`, then correct attribution and per-spec straight-through semantics. |
| 2 | Truthful gate kernel | high-assurance | Install exact parent-owned assertion attestation, producer-authenticated controller events, parent-content testing against a candidate target root, tree revalidation, verdict v4, structured blockers, reviewer attestation summary, and the real SPEC-015 regression. |

Dispatch 2’s trust-critical diff and tests receive independent human review. The operator records that review before installing the merged parent. The new gate’s tests are not represented as having been validated by a prior frozen verifier.

“Completed” means the repository delivery was reviewed and merged where applicable, the exact merged parent was installed by the root-owned launcher, the installation record was generated and verified, the on-box positive/negative controls passed, and no authoritative operation bypassed the launcher.

### 4.2 Per-dispatch allowed paths

All path allowances must expand to literal paths before authorization.

**Dispatch 0 — operator-installed trust foundation:**

- `/srv/codexwork/launcher/PLAN-003/`
- `/srv/codexwork/installed/<commit>/`
- `/srv/codexwork/venvs/gate/`
- the root-owned installation-record directory;
- the root-owned authoritative attempt-evidence root; and
- the root-only PR/push credential store and broker.

Repository changes, if needed for installation support, are limited to:

- `scripts/setup-worker-user.sh`
- a narrowly scoped root-launcher installation helper
- tests dedicated to launcher authority, installed-parent verification, and minimum dependency execution.

**Dispatch 1 — metrics:**

- `scripts/dispatch.py`, limited to extraction and lazy alias wiring
- `scripts/metrics_report.py`
- `scripts/delegation_report.py`
- `tests/metrics_report.sh`
- `tests/delegation_report.sh`
- `tests/dispatch_gate4.sh`, limited to alias and import-isolation coverage
- `tests/fixtures/metrics_semantics.json`

**Dispatch 2 — truthful gate:**

- `scripts/dispatch.py`, limited to test selection, trusted invocation, aggregation, tree checks, review parsing/evaluation, criteria persistence/binding, reviewer summary, and PR preflight
- `scripts/test`
- `scripts/test_runner.py`
- `scripts/lib/test_attest.sh`
- `scripts/test-policy.json`
- `scripts/verdict.schema.json`
- `scripts/setup-worker-user.sh`, limited to the controller/worker boundary and minimum gate environment
- the literal authorization-time output of `git ls-files 'tests/*.sh'`
- `tests/test_attestation.sh`
- `tests/verdict_integrity.sh`
- `tests/dispatch_gate4.sh`
- `tests/dispatch_parallel.sh`
- `tests/worker_isolation.sh`
- `tests/tree_binding.sh`
- `tests/trusted_snapshot.sh`
- `tests/fixtures/verdict_integrity/spec015_skips.log`
- `tests/fixtures/verdict_v4.json`
- `.github/workflows/ci.yml`, while retaining the single non-matrix job named `ci`

Any broader path requires explicit operator authorization.

### 4.3 Root-owned authority choke point

The launcher/service owns:

- authoritative attempt identity allocation;
- authoritative evidence-directory allocation;
- installed-parent selection;
- installation-record generation and verification;
- trusted controller execution;
- PR/push credentials;
- service-controlled refs; and
- brokered push and PR operations.

The repository dispatcher receives an attempt-bound launch context containing the authoritative attempt identity and exact installation-record digest. It never receives the underlying credential.

A direct repository invocation lacks a valid authoritative launch context and cannot allocate or write authoritative evidence or request brokered external effects. It may still create local files, processes, worktrees, reviews, or commits. Those effects are outside the authorization boundary.

Readmission of a direct-run commit creates a new attempt. The launcher ignores all direct-run artifact paths and digests, assigns a fresh identity, reruns required tests, obtains a fresh review, and creates a new service-controlled ref. Poisoned local artifacts are used in the regression to make accidental adoption detectable.

### 4.4 Simple installed-parent record

The operator installation flow:

1. Resolves the exact merged parent commit and tree.
2. Materializes the trusted kernel closure from Git objects into a new root-owned installed directory.
3. Verifies required test, helper, fixture, controller, inventory, and schema blobs.
4. Provisions and validates the minimum gate environment.
5. Records the exact parent and component identities in strict JSON.
6. Makes the installed directory and record non-worker-writable.
7. Configures the root-owned service to launch that exact installation.
8. Runs positive controls and required on-box negative drills.
9. Records the installation-record digest in every new authoritative attempt.

Before candidate work, the installed dispatcher measures itself and its trusted inputs and compares them with the selected record. Missing, malformed, duplicate-keyed, wrong-owner, worker-writable, or mismatched state refuses dispatch.

There is no activation ledger, append-only transition history, singleton head, CAS protocol, genesis form, rollback transition, or crash-durability claim. Operator installation and service configuration select the parent.

### 4.5 Attestation protocol

The parent inventory maps:

```json
{
  "test_id": "tests/example.sh",
  "parent_commit": "<commit>",
  "test_blob": "<git blob id>",
  "expected_assertion_ids": [
    "example.stable.condition",
    "example.error.path"
  ],
  "trust_class": "TRUST"
}
```

For each required invocation, the controller creates private state containing:

- a per-invocation nonce;
- test and parent bindings;
- candidate commit/tree binding;
- exact expected assertion set;
- source class;
- launch count; and
- trusted and supplemental channel identity.

A controller-produced event has the form:

```json
{
  "version": 1,
  "run_nonce": "<controller nonce>",
  "source_class": "trusted",
  "test_id": "tests/example.sh",
  "assertion_id": "example.stable.condition",
  "sequence": 1,
  "event": "assertion",
  "ok": true
}
```

The candidate does not produce this JSON. A parent-owned assertion definition asks the controller to launch a candidate command or inspect an outcome. After observing the result, the controller produces the event.

Before candidate launch, the service verifies distinct controller/candidate UIDs and process placement. Each candidate `exec` receives an allowlisted environment, no attestation material, and only allowlisted descriptors. Direct process-access denial is tested from the candidate side.

Aggregation rejects:

- an empty expected set;
- an absent required test;
- launch count other than one;
- any missing, duplicate, or unknown assertion ID;
- any `ok: false`;
- candidate-originated events;
- nonce, source, test, commit, or tree mismatches;
- malformed or inconsistent invocation records;
- skips and exit `77`; and
- aggregate-only evidence lacking real invocation records.

Every such rejection maps to `failed_test` before review.

### 4.6 Parent source and candidate target separation

Trusted test content is read from the installed parent. The candidate checkout is supplied as an explicit target root such as `TARGET_ROOT`; the parent source root is separately identified and non-worker-writable.

Trusted Python uses a safe working directory outside the candidate root. Candidate-root paths are passed as data. Candidate-modified tests run in a separate supplemental phase and write only supplemental results.

The dispatcher validates the candidate tree:

1. after all test and supplemental commands;
2. immediately before review; and
3. immediately before PR creation.

The first mismatch is a test failure. Later mismatches are review failures with the downstream spy at zero. Review diffs and PR commit identity come from Git objects.

### 4.7 Verdict v4 binding

At launch, the service persists:

- raw ordered acceptance criteria;
- normalized ordered acceptance criteria;
- one-based indices;
- vector digest;
- spec digest;
- base commit;
- candidate commit;
- installed-parent commit; and
- installation-record digest.

Review parsing proceeds in this order:

1. size bound;
2. strict JSON parse with duplicate-key rejection;
3. nonstandard-constant rejection;
4. v4 schema validation;
5. artifact and installed-parent bindings;
6. criteria-vector digest;
7. exact criterion count;
8. sequential indices;
9. positional normalized-text equality;
10. structured finding validation; and
11. binary evaluation.

Failure at any stage prevents PR creation.

### 4.8 Structured blocker predicate

Each of scope, regression, and security findings is an array of strict objects. `evaluate_binary_review()` repeats the complete structural and severity checks rather than relying solely on its caller.

An all-`MET` verdict is insufficient when any blocker exists. Advisory findings do not mechanically block authorization, consistent with R24’s planning stop-rule, but malformed findings fail closed.

### 4.9 Metrics implementation

Dispatch 1 has two ordered checkpoints:

1. **Extraction checkpoint:** capture operator-owned baselines and move metrics implementation into `scripts/metrics_report.py` without semantic change.
2. **Semantic checkpoint:** after parity passes, implement neutral attribution and spec-level straight-through calculations.

Window eligibility uses the final spec terminal timestamp, while classification reads the spec’s complete retained attempt history. This prevents retries outside the reporting window from being misclassified as straight-through.

### 4.10 Minimum gate environment

The operator provisions a fixed root-owned environment sufficient to run the required parent tests. The installation record captures:

- requirements-file digest;
- interpreter path and version;
- package versions; and
- resolved module origins for `yaml` and `jsonschema`.

The trusted process starts from a safe directory with Python environment variables scrubbed. Missing or wrong-origin imports fail; they do not skip. Candidate requirements are not installed.

This mechanism intentionally stops before content-addressed venv identities, ABI/platform branching, a wheelhouse, shadow-module ladders beyond the necessary attacks, and fresh-box provisioning certification.

### 4.11 Reviewer evidence

The reviewer prompt contains the machine-generated attestation summary before any model judgment. It includes required IDs, expected and observed assertion sets, invocation counts, source bindings, candidate and parent identities, process-separation results, and final test status.

Raw logs remain retained evidence but are not prompt-injected. Sanitized tail selection, delimiter hardening, and semantic-injection claims are outside this plan.

### 4.12 Required-test changes

When a candidate changes a required trust test, helper, or fixture:

1. the installed old blob remains authoritative for the candidate attempt;
2. the changed blob runs only as supplemental;
3. independent human review evaluates the trust-critical diff;
4. explicit authorization records the old and new Git blob IDs;
5. after merge, the operator installs the new parent and records the new inventory; and
6. the new blob becomes authoritative only for later attempts.

This is the only compatibility rule in the kernel. The multi-stage bridge/promotion sequence remains deferred.

### 4.13 Alternatives considered

1. **Continue trusting aggregate exit zero.** Rejected because it reproduces SPEC-015.

2. **Require at least one assertion.** Rejected because a trivial assertion can conceal omitted substantive checks.

3. **Accept candidate assertion JSON with a nonce.** Rejected because inherited or stolen nonces do not authenticate the producer.

4. **Run the controller as `codex-worker`.** Rejected because same-UID process-access mechanisms can expose or alter controller state.

5. **Run required tests from the candidate checkout.** Rejected because candidate-modified tests would authorize themselves.

6. **Treat `test_command: true` as evidence.** Rejected because it identifies no required assertion.

7. **Use reviewer judgment to detect missing tests.** Rejected because missing required evidence is mechanically decidable.

8. **Retain the full revision-6 bootstrap verifier and activation protocol.** Deferred by R24 in favor of the choke point, simple operator installation, and independent human review.

9. **Inject a sanitized log tail.** Deferred. The machine attestation summary is the primary reviewer evidence.

10. **Unblock Phase 2 after metrics.** Rejected because corrected metrics do not close the false-pass path.

## 5. Affected boundaries & consumers

| Boundary or consumer | Effect |
|---|---|
| Root-owned launcher/service | Becomes the exclusive authority for attempt identity, authoritative evidence allocation, installed-parent selection, and PR/push operations. |
| Installation record | Binds the exact installed parent, trusted components, inventory, verdict schema, and minimum dependency environment. |
| Direct repository dispatcher | May produce only local non-authoritative effects without a launcher-issued context. |
| Direct-run commit | May be submitted only as untrusted input to a fresh authoritative attempt. |
| Authoritative evidence root | Becomes non-worker-writable and accessible only through the launcher/service. |
| PR/push credential | Remains behind the service and is never passed to repository or candidate processes. |
| Installed parent | Supplies dispatcher, controller, required tests, helpers, fixtures, inventory, and verdict schema. |
| Candidate worktree | Supplies only the target under test and supplemental test content. |
| Trusted controller | Runs outside the candidate UID/process namespace and is the sole assertion-event producer. |
| `codex-worker` | Receives no nonce, assertion descriptor, authoritative evidence path, or credential. |
| `scripts/test` users | Receive exact assertion-ID semantics and explicit skip/failure diagnostics. |
| Required trust tests | Gain stable test/assertion IDs, exact expected sets, positive controls, and per-assertion mutation drills. |
| Candidate test changes | Stay supplemental until separately reviewed, explicitly old/new-blob authorized, merged, and installed. |
| Reviewer | Receives the machine attestation summary; raw logs are not injected. |
| `scripts/verdict.schema.json` | Becomes strict authorization schema v4. |
| Attempt manifest | Gains the persisted criteria vector, vector digest, installed-parent bindings, and attestation summary. |
| Legacy verdict consumers | Remain display-only and must be inventoried. |
| Metrics consumers | Receive neutral attribution and spec-level complete-history semantics. |
| CI | Remains portable validation and cannot substitute for the authoritative on-box launcher boundary. |
| Phase 2 | Remains blocked until the entire three-dispatch kernel is installed and validated. |
| Historical SPEC-015 evidence | Remains immutable regression input. |
| Evidence-hashing plan | Retains ownership of comprehensive evidence sealing and no-replace coverage. |

## 6. Ordered implementation steps

1. Freeze the current parent commit/tree, integration tip, SPEC-015 hashes, metrics outputs, required test inventory, and current interpreter/dependency state.

2. Independently review the root-owned launcher, installation-record format, authoritative evidence permissions, and credential broker.

3. Install the exact current parent from Git objects under `/srv/codexwork/installed/<commit>`.

4. Provision the minimum root-owned gate environment with PyYAML and jsonschema and verify trusted import origins.

5. Generate the installation record and verify worker write denial across the installed parent, record, environment, authoritative evidence root, and credential store.

6. Prove direct `scripts/dispatch` invocation leaves authoritative evidence untouched and push/PR spies at zero.

7. Produce a local commit through a direct run, poison its local evidence and review artifacts, and readmit only the commit through a fresh launcher attempt. Prove fresh identity, evidence, tests, review, ref, push, and PR handling.

8. Capture operator-owned metrics baselines before candidate metrics work.

9. Add extraction parity and non-metrics import-isolation regressions.

10. Extract metrics into `scripts/metrics_report.py` while preserving baseline behavior.

11. Add complete-history, terminal-window, zero-denominator, neutral-attribution, and five-spec semantic fixtures.

12. Implement corrected attribution and per-spec straight-through semantics.

13. Independently review, merge, install, and verify Dispatch 1.

14. Assign every required test a stable parent-owned test ID and exact expected assertion-ID set.

15. Classify substantive assertions as TRUST or non-TRUST.

16. Add a positive control and induced-failure mutation drill for every substantive TRUST assertion.

17. Implement the root-owned installed test source and explicit candidate target-root contract.

18. Implement the controller/candidate UID and process-namespace preflight.

19. Implement per-invocation nonces, separate trusted/supplemental channels, environment scrubbing, descriptor closure, and controller-only event production.

20. Add environment, descriptor, `/proc`, `ptrace`, process-VM, and `pidfd_getfd` forgery attacks.

21. Implement exact-set aggregation, single-launch accounting, and fail-before-review transitions.

22. Add post-test, pre-review, and pre-PR candidate-tree revalidation.

23. Persist the exact digest-approved acceptance-criteria vector at launch.

24. Implement strict JSON parsing, duplicate-key and nonstandard-constant rejection, schema v4, exact positional criteria binding, and legacy display-only handling.

25. Implement structured finding arrays and the defensive blocker predicate inside `evaluate_binary_review()`.

26. Add the machine attestation summary to the reviewer prompt and keep raw logs out of the prompt.

27. Add the real SPEC-015 state-machine replay with reviewer and PR spies.

28. Run every positive control, mutation drill, forged-event test, tree-mutation test, verdict-v4 case, and SPEC-015 replay on-box.

29. Independently review every trust-critical Dispatch 2 diff, including its tests and assertion inventory.

30. For any changed required trust test/helper/fixture, record explicit human authorization naming its old and new blob IDs.

31. Merge Dispatch 2, install the exact merged parent, provision its minimum gate environment, generate the new installation record, and rerun all on-box validation.

32. Mark Phase 2’s PLAN-003 prerequisite satisfied only after all three dispatches meet R8.7.

## 7. Failure modes & blast radius

| Trigger | Consequence | Mitigation |
|---|---|---|
| Direct repository dispatcher is invoked | Local compute, files, worktrees, reviews, or commits may be created | Those effects are non-authoritative; evidence and credential boundaries remain service-only. |
| Direct-run artifacts are adopted | Untrusted claims could enter an authoritative attempt | Poisoned-artifact regression; fresh identity, evidence, tests, review, ref, and PR operations are mandatory. |
| Installed parent differs from its record | Wrong gate code or inventory could execute | Pre-attempt measurement and exact record comparison refuse launch. |
| Operator selects a stale installation | An older but internally consistent gate may run | Manual installation selection is recorded and independently reviewed; stronger stale-parent exclusion is deferred. |
| Required dependency is absent | Trust tests might skip again | Missing or wrong-origin dependencies fail before tests and review. |
| One trivial assertion runs | Partial execution could appear successful | Exact expected assertion-set equality. |
| Candidate forges event data | False trusted PASS | Controller-only event production, nonce/FD non-inheritance, separate UIDs/namespaces, and direct process-access denial. |
| Controller/candidate separation is unavailable | Candidate may reach trusted state | Abort before candidate launch; no fallback. |
| Trusted and supplemental results collide | Candidate test may satisfy a required ID | Separate channels, nonces, source bindings, and aggregation namespaces. |
| Required test launches twice | Selective result retention may hide a failure | Exact-one launch count and side-effect counter. |
| Candidate changes required test | New test may self-promote | Old parent blob remains authoritative; explicit old/new-blob human authorization is required for later installation. |
| Candidate mutates its tree after tests | Reviewer or PR could receive different content | Post-test, pre-review, and pre-PR tree revalidation. |
| Criteria are omitted or reordered | Subset review could authorize PASS | Exact count, order, indices, normalized text, and vector digest. |
| Verdict contains duplicate keys | Human and machine interpretations may differ | Strict duplicate-key rejection at every nesting level. |
| Findings are malformed or contain blockers | Reviewer output may be mis-evaluated | Defensive blocker predicate inside the evaluator. |
| Metrics extraction changes behavior | Phase 2 measurements lose continuity | Operator-captured parity baseline before semantic changes. |
| Retry occurs outside reporting window | Straight-through rate may be inflated | Final-terminal-time anchoring plus complete-history classification. |
| Negative trust test fails for the wrong reason | Vacuous validation may appear effective | Mandatory positive controls paired with mutation drills. |
| Reviewer is influenced by candidate diff | Advisory judgment may be manipulated | Mechanical invariants finish before review; blocker structure is machine-evaluated. |
| Kernel tests contain a semantic defect | A flawed new gate may be installed | Independent human review of every trust-critical diff and explicit test-blob authorization; frozen prior verifier is a recorded deferred hardening. |

The worst in-scope consequence is an incorrectly authorized control-plane PR. On detection, stop new launcher attempts, disable PR/push brokerage, preserve all evidence, and reinstall the last independently reviewed known-good parent.

## 8. Validation plan

### 8.1 Regressions that fail before implementation

1. An exit-zero required skip reaches PASS.
2. A required test emits one trivial assertion while omitting substantive checks.
3. A candidate observes inherited attestation state in a naïve controller.
4. A same-UID candidate attempts `ptrace`, process-VM, or `pidfd_getfd` access.
5. A candidate-modified required test can be confused with parent-required content.
6. A candidate mutates its worktree after a successful test result.
7. A conventional JSON parser accepts duplicate keys.
8. A verdict with N−1 all-`MET` criteria reaches binary evaluation.
9. A blocker is missed when malformed findings bypass schema validation.
10. Required Python tests skip because PyYAML/jsonschema are absent.
11. A direct repository dispatcher enters local work without proving authoritative launcher provenance.
12. Current metrics disagree with neutral attribution and spec-level complete-history semantics.
13. A fixture-only SPEC-015 adapter fails without proving the production state-machine transition.
14. A negative isolation test passes merely because its positive setup was broken.

### 8.2 Launcher, installation, and choke-point validation

- Verify root ownership and worker write denial for installed parent content, installation records, the gate environment, evidence roots, and credential storage.
- Mutate each recorded trusted component and require refusal before candidate launch.
- Substitute the installation-record digest in a launch context and require refusal.
- Invoke repository `scripts/dispatch` directly as the ordinary operator and as `codex-worker`; require authoritative evidence to remain unchanged and push/PR spies to remain at zero.
- Confirm the direct run may create only local non-authoritative effects.
- Poison direct-run evidence, verdicts, attestations, test results, and attempt identity; submit only its commit to the launcher; prove none of the poisoned artifacts or digests is adopted.
- Require a new attempt identity, fresh controller invocation records, fresh review, a service-controlled ref, and broker-only push/PR operations.
- Attempt to make `codex-worker` replace the installation record, inventory, required test, helper, fixture, schema, or environment and require denial.
- Change a required trust test without old/new-blob authorization and require refusal to install it as parent content.
- Provide authorization naming the wrong old or new blob and require refusal.
- Verify the changed test remains supplemental during its introducing attempt.

### 8.3 Metrics validation

- Compare extraction output with the operator-captured baseline.
- Prove candidate fixtures cannot update the baseline.
- Invoke metrics through the legacy alias and standalone module.
- Make `scripts/metrics_report.py` unavailable and prove representative non-metrics commands remain unaffected.
- Verify `not_attributed_to_orchestrator` in text, JSON, help, and headings.
- Verify the five-spec fixture returns numerator `1`, denominator `3`, rate `1/3`, excluded-in-progress `1`, and malformed/incomplete `1`.
- Add a retry before the window and prove it prevents straight-through classification.
- Add a later attempt and prove the canonical final terminal anchor moves.
- Verify zero denominator returns JSON `null` and display `N/A`.
- Verify no authorization, attestation, review, evidence, credential, or PR path changed.

### 8.4 Attestation and producer-authentication validation

- Run each required test with its exact expected assertion set.
- Remove each substantive assertion individually and require `missing_assertions`.
- Duplicate each assertion ID and require rejection.
- Add an unknown assertion ID and require rejection.
- Set an expected assertion set to empty and require rejection.
- Exercise exit zero with no assertions and require `failed_test`.
- Exercise diagnostic exit `77` and require `failed_test`, not successful skip.
- Remove a required test and require `failed_test`.
- Corrupt nonce, source class, test ID, parent commit, candidate commit, or sequence and require rejection.
- Submit candidate-authored assertion JSON and require it to remain supplemental/untrusted.
- Race trusted and supplemental invocations using identical test and assertion IDs.
- Launch a required test twice and retain one result; require the launch counter to fail.
- Supply a fabricated aggregate without invocation records and require rejection.
- Collapse controller/candidate UID or process separation and require abort before candidate launch.
- From `codex-worker`, attempt:

  - inherited environment discovery;
  - inherited assertion-FD discovery;
  - `/proc/<ppid>/environ`;
  - `/proc/<ppid>/fd`;
  - `ptrace`;
  - `process_vm_readv`;
  - `process_vm_writev`; and
  - `pidfd_getfd`.

  Each must fail without reading, modifying, duplicating, or producing accepted controller state.

- Verify the candidate environment contains no nonce or attestation variables.
- Verify only allowlisted descriptors survive every candidate `exec`.
- Verify every attestation failure occurs before reviewer invocation and leaves reviewer and PR spies at zero.

### 8.5 Parent-content and tree-binding validation

- Verify every required test, helper, fixture, controller, inventory, and schema against its recorded parent Git blob.
- Place conflicting copies in the candidate tree and prove the parent copies execute.
- Modify a required test in the candidate and prove it is supplemental only.
- Emit a trusted test ID from a supplemental process and prove it cannot satisfy the parent result.
- Run required tests with parent source and candidate target roots and prove the roots are distinct.
- Mutate tracked candidate content after successful command completion and require post-test `failed_test`.
- Add forbidden untracked control-plane content and require failure.
- Mutate the worktree between post-test validation and review and require no reviewer call.
- Mutate the worktree between review and PR creation and require no PR call.
- Verify review diff and PR identity derive from bound Git objects.
- Verify a candidate policy change cannot reduce its own selected test set.

### 8.6 Verdict v4 validation

The installed parent inventory must assign one required test ID for the verdict-v4 contract and an exact expected assertion set containing every ID below. During the introducing candidate attempt, candidate-modified copies are supplemental; after independent review, merge, explicit authorization where required, and operator installation, the installed parent copy becomes authoritative.

| Validation case | Exact assertion ID |
|---|---|
| N correct criteria eligible | `v4.criteria.exact_n_eligible` |
| N−1 criteria reject | `v4.criteria.n_minus_1_reject` |
| N+1 criteria reject | `v4.criteria.n_plus_1_reject` |
| Duplicate criterion reject | `v4.criteria.duplicate_reject` |
| Reordered criteria reject | `v4.criteria.reordered_reject` |
| Wrong criterion index reject | `v4.criteria.wrong_index_reject` |
| Invented criterion text reject | `v4.criteria.invented_text_reject` |
| Exact text binds | `v4.normalization.exact_text_binds` |
| NFKC/whitespace-normalized text binds | `v4.normalization.nfkc_whitespace_binds` |
| Case change rejects | `v4.normalization.case_change_reject` |
| Punctuation change rejects | `v4.normalization.punctuation_change_reject` |
| Markdown change rejects | `v4.normalization.markdown_change_reject` |
| Wording change rejects | `v4.normalization.wording_change_reject` |
| Duplicate top-level key rejects | `v4.json.duplicate_top_level_reject` |
| Duplicate criterion key rejects | `v4.json.duplicate_criterion_reject` |
| Duplicate finding key rejects | `v4.json.duplicate_finding_reject` |
| Duplicate severity key rejects | `v4.json.duplicate_severity_reject` |
| Duplicate binding key rejects | `v4.json.duplicate_binding_reject` |
| Nonstandard constants reject | `v4.json.nonstandard_constants_reject` |
| Spec-path replacement leaves persisted vector authoritative | `v4.vector.spec_replacement_ignored` |
| Wrong spec binding rejects | `v4.binding.wrong_spec_reject` |
| Wrong base binding rejects | `v4.binding.wrong_base_reject` |
| Wrong worker binding rejects | `v4.binding.wrong_worker_reject` |
| Wrong vector binding rejects | `v4.binding.wrong_vector_reject` |
| Wrong installed-parent binding rejects | `v4.binding.wrong_parent_reject` |
| Wrong installation-record binding rejects | `v4.binding.wrong_installation_reject` |
| Scope blocker rejects | `v4.findings.scope_blocker_reject` |
| Regression blocker rejects | `v4.findings.regression_blocker_reject` |
| Security blocker rejects | `v4.findings.security_blocker_reject` |
| Empty finding arrays remain eligible | `v4.findings.empty_arrays_eligible` |
| Advisory-only arrays remain eligible | `v4.findings.advisory_arrays_eligible` |
| Direct malformed evaluator input rejects | `v4.findings.direct_evaluator_malformed_reject` |
| Undeclared properties reject | `v4.schema.undeclared_properties_reject` |
| v1 remains display-only | `v4.legacy.v1_display_only` |
| v2 remains display-only | `v4.legacy.v2_display_only` |
| v3 remains display-only | `v4.legacy.v3_display_only` |
| Legacy display-consumer inventory complete | `v4.legacy.consumer_inventory_complete` |
| Every rejected review leaves PR spy at zero | `v4.pr.rejection_zero_calls` |

The expected set is exactly the complete set above. Missing, duplicate, or unknown IDs fail under R2.

### 8.7 Minimum environment validation

- Remove PyYAML and require pre-test failure, not skip.
- Remove jsonschema and require pre-test failure, not skip.
- Resolve either module outside the configured environment and require refusal.
- Add candidate `yaml.py`, `jsonschema.py`, `sitecustomize.py`, and `usercustomize.py`; prove none loads into trusted execution.
- Set hostile `PYTHONPATH`, `PYTHONHOME`, `PYTHONSTARTUP`, and user-site variables; prove they are scrubbed.
- Run trusted Python from the candidate root and require the harness to reject the configuration.
- Attempt worker modification of the gate environment and require denial.
- Attempt candidate dependency installation during validation and require denial.
- Run a positive control proving the correctly provisioned environment executes the substantive required assertions.

### 8.8 SPEC-015 and non-vacuous end-to-end validation

- Preserve and hash the existing SPEC-015 evidence before replay.
- Enter through the actual production gate state machine.
- Require `legacy_missing_attestation` to map to `failed_test`.
- Require reviewer and PR spies at zero.
- Verify original SPEC-015 bytes remain unchanged.
- Verify fixture-only adapter success is insufficient.
- Verify constructed aggregates cannot authorize the replay.
- Pair every substantive TRUST mutation with an unmutated positive control.
- Prove each mutation reaches the intended condition rather than failing during unrelated setup.
- Run focused tests, `./scripts/test`, on-box isolation tests, and the complete production replay.

### 8.9 Requirement-to-validation traceability

| Requirement | Primary validation |
|---|---|
| R1 | §8.2 |
| R2 | §8.4 and §8.8 |
| R3 | §8.5 |
| R4 | §8.6 |
| R5 | §8.6 |
| R6 | §8.3 |
| R7 | §8.7 |
| R8 | §8.8 |

## 9. Rollback / irreversibility

1. Stop new launcher-controlled attempts and disable PR/push brokerage.

2. Preserve all authoritative and local diagnostic evidence.

3. Identify the last independently reviewed, known-good installed parent and verify its commit, tree, trusted-component digests, inventory, schema, and environment.

4. Operator-install that parent and generate a new installation record.

5. Configure the root-owned service to use the verified installation.

6. Run its positive controls, isolation drills, and required false-pass regressions before reopening dispatch.

7. Do not reinterpret, overwrite, or adopt evidence from failed or direct runs.

8. A metrics-only rollback blocks Phase 2 until extraction parity and corrected semantics are restored.

9. A verdict-v4 rollback must preserve legacy displayability but must not restore v1–v3 authorization.

10. A test-attestation rollback must not restore exit-code-only authorization. If no truthful known-good parent is available, dispatch remains stopped.

11. Installed snapshots and environments may remain inert for forensic or rollback use.

12. SPEC-015 and existing attempts remain irreversible evidence.

13. This rollback is an operator-run installation procedure. It does not claim append-only activation history, atomic CAS selection, concurrent installer exclusion, or crash-durable transition semantics.

## 10. Open questions / operator decisions

None within this plan.

R24 authorizes the scope trim. Any later expansion into a deferred item requires its named future specification or a new operator decision.

A required trust-test change that lacks explicit human authorization naming both old and new blob IDs remains blocked; PLAN-003 grants no implicit compatibility or emergency-bootstrap authority.

## 11. Provenance

- **Challenge and revisions 2–3:** Established exact assertion inventories, controller-owned evidence, tree revalidation, parent test content, strict verdict binding, metrics semantics, non-vacuous validation, and the original operational hardening set.

- **Revision 4:** Added the authoritative evidence/credential choke point, embedded bootstrap approval handling, full activation state machine, and controller/candidate UID boundary.

- **Revision 5:** Narrowed direct-run prohibition to authoritative effects, clarified active-head history semantics, and specified crash-phase activation promises.

- **Revision 6:** Permitted direct-run commit readmission as untrusted input while prohibiting artifact adoption; added the frozen Dispatch 5 oracle; separated activation creation and selection identities; and narrowed durability claims to process-crash consistency.

- **Operator decision R24:** Authorized the Phase-1 trimmed truthful kernel, deferred self-gating hardening beyond the false-pass closure, replaced frozen profiles with the choke point plus human review, and replaced the activation state machine with simple operator installation and recorded digests.

- **Revision 7:** Applies R24 without re-litigating it. All revision-6 mechanisms inside the kernel remain at full depth. Every mechanism outside the kernel is assigned below to a future specification with its accepted risk recorded.

- **Authorization:** Pending adversarial review under R24’s stop-rule and an authorized revision-7 digest. Zero security-material and executability-blocking findings authorizes the plan; advisory notes and already recorded residuals do not block it.

## Deferred (recorded, not cancelled)

### D1. Full activation state machine

**Deferred item:** Append-only activation ledger, atomic singleton active head, CAS transitions, strict genesis form, rollback transitions, creation-versus-selection identities, exact fsync ordering, sibling exclusion, stale-parent refusal, and SIGKILL crash-phase durability oracles.

**Why deferred:** R24 replaces this machinery with operator-run installation, an installation record containing the installed parent commit and digests, and a dispatcher check that its measured parent matches that record.

**Risk accepted:** Parent selection remains an operator/service-configuration action. PLAN-003 does not mechanically exclude concurrent installers, stale but internally valid installation selection, or crash ambiguity during reconfiguration.

**Future-spec owner:** `activation-state-machine`.

### D2. Frozen bootstrap verifier profiles

**Deferred item:** Dispatch 0’s frozen per-dispatch profiles, frozen expected-assertion inventories for Dispatches 1–5, independently frozen Dispatch 5 verdict oracle, and prior-verifier authorization of the new gate.

**Why deferred:** R24 substitutes the authoritative choke point and independent human review of every trust-critical diff.

**Risk accepted:** Candidate code cannot create authoritative evidence or reach credentials, but the new gate’s own tests are reviewed by humans rather than mechanically validated by a prior frozen verifier.

**Future-spec owner:** `bootstrap-frozen-verifier`.

### D3. Content-addressed gate environment and dependency hardening

**Deferred item:** Requirements/ABI/platform-addressed venv identity, shared immutable venv ladder, wheelhouse and transitive artifact hashing, Python-version coexistence drills, full shadow-module/ABI matrix, staged dependency-promotion protocol, and fresh-box provisioning certification beyond the minimum needed to execute required tests.

**Why deferred:** The observed bug requires PyYAML/jsonschema to execute reliably; it does not require a complete dependency supply-chain design.

**Risk accepted:** The kernel records interpreter, requirements, package versions, and module origins but does not prove reproducibility across every ABI, platform, or package artifact source.

**Future-spec owner:** `gate-environment-hardening`.

### D4. Sanitized reviewer log-tail machinery

**Deferred item:** Bounded tail selection, line and byte limits, JSON escaping, delimiter integrity, control-character filtering, race-safe log reopening, and prompt injection of a secondary raw-log tail.

**Why deferred:** The machine attestation summary is the primary evidence needed to close false-pass certification. Raw logs remain retained but are not prompt-injected.

**Risk accepted:** Reviewers lose convenient in-prompt log context and must inspect retained logs separately. Existing raw-log capture may still carry availability risk until hardened.

**Future-spec owner:** `reviewer-evidence-hardening`.

### D5. Full evidence sealing and comprehensive no-replace suite

**Deferred item:** Systematic `O_CREAT|O_EXCL` coverage, hardlink/symlink/rename-swap defenses across all artifacts, terminal attempt manifests, retained-evidence hash chains, directory durability, finalized-attempt sealing, and comprehensive evidence-integrity recovery.

**Why deferred:** This work is already routed to the evidence-hashing plan. The kernel relies on the root-owned evidence choke point and fresh service-issued attempt directories.

**Risk accepted:** Candidate code cannot write authoritative evidence, but comprehensive post-creation tamper detection and crash-durable sealing are not established by PLAN-003.

**Future-spec owner:** `evidence-hashing`.

### D6. Multi-stage trust-test compatibility promotion

**Deferred item:** The two- or three-stage bridge sequence consisting of transitional behavior, transitional test promotion, strict-new test promotion, and later bridge removal.

**Why deferred:** The kernel keeps only the rule necessary to prevent self-promotion: an incompatible required-test change needs explicit human authorization naming the old and new blobs, and the candidate copy remains supplemental during its own attempt.

**Risk accepted:** Some legitimate behavior changes may require operator intervention or remain blocked because PLAN-003 provides no automated compatibility bridge.

**Future-spec owner:** `trust-test-compatibility-promotion`.

### D7. Exhaustive canonical policy classification

**Deferred item:** Complete-tree path-map comparison for every mode, symlink, object type, submodule, `.gitmodules`, rename side, unknown root path, generated control-plane file, and the property that every changed path maps to a nonempty required-test set or a policy error.

**Why deferred:** The kernel needs parent selection for identified trust-critical files and immutable commit-based review inputs, but R24 does not retain the full policy-exhaustiveness program.

**Risk accepted:** A path category outside the kernel’s explicit trust-critical inventory may receive insufficient automatic test selection and depend on human review.

**Future-spec owner:** `control-plane-policy-coverage`.

### D8. Full installed-closure and interpreter TOCTOU hardening

**Deferred item:** Whole-gate closure manifests, verified interpreter identities, already-open script descriptors, beneath-only resolution, directory-component race tests, and no-reopen execution for every runner, helper, fixture, schema, and interpreter.

**Why deferred:** The kernel verifies and installs the exact parent blobs necessary for required tests and keeps them root-owned and non-worker-writable. The broader closure and pathname-race program exceeds the trimmed false-pass repair.

**Risk accepted:** The candidate cannot rewrite the installed parent, but replacement or misconfiguration by a privileged administrator and broader interpreter/path identity drift are not covered exhaustively.

**Future-spec owner:** `trusted-gate-closure`.

### D9. Full approval-schema/bootstrap authorization system

**Deferred item:** The independently frozen embedded approval parser/schema and its complete bindings for every dispatch profile, baseline, verifier, activation, and changed artifact.

**Why deferred:** With frozen profiles and activation transitions deferred, the kernel requires only machine-readable operator installation records and explicit old/new test-blob authorization.

**Risk accepted:** Approval semantics for the trimmed installation flow are narrower and remain more dependent on operator procedure than the revision-6 frozen bootstrap design.

**Future-spec owner:** `approval-schema`.

### D10. Read-only candidate mount and continuous tree immutability

**Deferred item:** A read-only bind mount or equivalent mechanism preventing candidate-tree mutation throughout testing and review.

**Why deferred:** R24 retains transition-time tree revalidation as the kernel requirement.

**Risk accepted:** A mutation and restoration between checks may evade clean-tree observations, although review and PR inputs remain bound to Git commit objects.

**Future-spec owner:** `candidate-tree-immutability`.

### D11. Portable/on-box activation certification

**Deferred item:** CI-versus-on-box activation artifacts, required post-merge activation drills, fresh-machine provisioning, and machine-enforced prevention of CI PASS substituting for installed-parent activation.

**Why deferred:** The trimmed flow uses operator installation and required on-box validation without a formal activation state machine.

**Risk accepted:** The distinction is procedural and recorded rather than enforced through an activation manifest/ledger protocol.

**Future-spec owner:** `activation-state-machine`, coordinated with `gate-environment-hardening`.

## Residual risks (recorded)

1. **Human-reviewed bootstrap residual:** The new gate’s trust tests are independently reviewed by humans rather than certified by a prior frozen verifier. This is the principal residual explicitly accepted by R24.

2. **Manual installed-parent selection:** Installation records prove what a dispatcher is running but do not provide CAS selection, stale-parent exclusion, concurrent transition serialization, or durable activation history.

3. **Test semantic sufficiency:** Exact assertion execution cannot prove that the assertions express the right security property. Positive controls, per-assertion mutations, and human review reduce but do not eliminate this risk.

4. **Candidate-tree race window:** Revalidation occurs after tests, before review, and before PR creation, but no read-only candidate mount prevents mutation and restoration between checks.

5. **Incomplete automatic policy coverage:** The kernel protects enumerated trust-critical files. Full repository path-classification exhaustiveness is deferred.

6. **Dependency supply-chain completeness:** The minimum environment proves that required dependencies execute from the expected root-owned environment. It does not establish a content-addressed, ABI-complete, or fully hash-locked supply chain.

7. **Evidence sealing completeness:** The root-owned choke point prevents candidate-written authoritative evidence, but comprehensive sealing, hash chaining, and crash-durable no-replace behavior remain with the evidence-hashing plan.

8. **Reviewer semantic influence:** Candidate-controlled diffs can still influence reviewer judgment. Mechanically decidable invariants are resolved before review, but advisory reasoning remains model-mediated.

9. **Reduced reviewer context:** Raw logs are retained but not prompt-injected. The reviewer may need separate human-assisted log inspection for diagnostic context.

10. **Direct-run local effects:** Direct invocation may waste compute or create confusing local worktrees, processes, reviews, and commits. None has authoritative effect, but operator confusion remains possible.

11. **Privileged administrator threat:** Root-owned installation prevents candidate modification, not malicious or mistaken root replacement. Full closure and activation hardening are deferred.

12. **Compatibility availability:** An incompatible trust-test change may remain blocked until explicit human authorization or the future compatibility-promotion specification supplies a staged path.

13. **No activation crash oracle:** PLAN-003 makes no process-crash, power-loss, or faulting-filesystem durability claim for parent installation or service reconfiguration.

## Disposition record (revision 7)

- **Kept — exact machine test attestation.** Parent-owned required-test IDs and exact expected assertion-ID sets remain mandatory. Skip, missing test, zero assertions, missing/unknown/duplicate IDs, malformed provenance, and fabricated aggregates become `failed_test` before review. Aggregate exit zero is non-evidentiary.

- **Kept — producer-authenticated events.** The controller remains outside the candidate UID and process namespace; candidate environment and descriptors are scrubbed before every `exec`; trusted and supplemental invocations use separate pipes and nonces; only the controller produces accepted events; `/proc`, `ptrace`, process-VM, and `pidfd_getfd` attacks remain mandatory negative tests.

- **Kept — parent-content required tests.** Required tests, helpers, and fixtures remain Git-blob-verified parent content executed against the candidate as a separate target root. Candidate-modified copies remain supplemental.

- **Kept — tree revalidation.** Candidate `HEAD`, tree identity, cleanliness, and forbidden untracked state are checked after tests, before review, and before PR creation.

- **Kept — verdict schema v4.** Exact criterion count, order, normalized-text binding, `criterion_index`, strict duplicate-key and nonstandard-constant rejection, launch-time criteria-vector persistence, and exact artifact/parent bindings remain.

- **Kept — structured blockers.** Scope, regression, and security findings remain strict `advisory|blocker` arrays, with the mechanical fail-closed predicate repeated inside `evaluate_binary_review()`.

- **Kept — credential/evidence choke point.** Authoritative evidence and PR/push credentials remain reachable only through the root-owned launcher. Direct-run artifacts are never adopted; only a resulting commit may be readmitted as untrusted input to a fresh service-controlled attempt.

- **Kept — metrics.** Behavior-preserving extraction into `scripts/metrics_report.py`, neutral `not_attributed_to_orchestrator` labeling, per-spec complete-history straight-through semantics, and `null`/`N/A` zero-denominator behavior remain Phase 2 prerequisites.

- **Kept — minimum executable dependencies.** Root-owned PyYAML/jsonschema provisioning and origin verification remain because required tests must execute rather than skip.

- **Kept — real SPEC-015 replay and non-vacuous controls.** The production state-machine replay, zero reviewer/PR spies, positive controls, and per-substantive-TRUST-assertion mutation drills remain mandatory.

- **Deferred to `activation-state-machine`.** The append-only activation ledger, singleton CAS head, genesis/rollback forms, exact durability barriers, crash oracles, stale-parent exclusion, and formal portable/on-box activation certification.

- **Deferred to `bootstrap-frozen-verifier`.** Per-dispatch frozen profiles and the independently frozen Dispatch 5 oracle. The accepted replacement is the choke point plus independent human review of every trust-critical diff.

- **Deferred to `gate-environment-hardening`.** Content-addressed ABI/platform venvs, wheelhouse and transitive dependency proof, broad shadow-module ladders, and fresh-box provisioning certification.

- **Deferred to `reviewer-evidence-hardening`.** Sanitized bounded log-tail construction and prompt injection beyond the machine attestation summary.

- **Deferred to `evidence-hashing`.** Full evidence sealing, terminal hash manifests, directory durability, and comprehensive no-replace attack coverage.

- **Deferred to `trust-test-compatibility-promotion`.** The two/three-stage compatibility bridge. The kernel retains explicit human authorization naming old and new blobs.

- **Deferred to `control-plane-policy-coverage`, `trusted-gate-closure`, `approval-schema`, and `candidate-tree-immutability`.** Full path-policy exhaustiveness, broad descriptor/interpreter closure hardening, frozen approval semantics, and read-only candidate mounts are recorded with their accepted risks above.

No accumulated fix inside the R24 truthful kernel was lost.
