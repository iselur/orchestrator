PLAN-004 revision 4 is substantially improved, but three execution-level defects remain material.

1. The durability rule is not executable for every dispatch call site.

Sections: §1 capture points, requirements 18–19, §4.7 “Dispatch transport,” P2-02 acceptance, §8.4.

The plan universally requires lifecycle, concurrency, and Claude-envelope emission only after “the corresponding canonical transition and evidence write are durable.” The quoted current-state evidence identifies durable launch, result, review, and attestation artifacts, but no durable canonical artifact for concurrency transitions—and potentially none for lifecycle-start or process-start identity. A semaphore acquisition or subprocess start is an in-memory event, not a durable evidence write.

Consequently, P2-02 cannot both emit all promised record classes and prove its stated durability ordering without either:

- adding a new synchronous canonical write to dispatch, violating the limited-emitter boundary; or
- treating an in-memory transition as “durable,” contradicting the acceptance language.

Minimal amendment: add a call-site table naming every emitted record, exact transition, exact pre-existing durable artifact and durability barrier. For transitions without such an artifact, explicitly define them as post-transition observation-only records, remove the claim that canonical evidence exists for them, and test only that emission occurs after the scheduling/process transition has completed. Do not introduce a new canonical measurement-related write.

2. Runtime attestation is asserted but has no defined trust mechanism or production implementation owner.

Sections: requirement 21, §4.6 “Semantic epoch,” §4.7 materialization, P2-03, P2-06, and §8.4–8.5.

Trusted journald metadata adequately distinguishes the dispatcher unit from a D5 worker, assuming the stated profile checks. It does not identify the Python modules or checkout actually executed: `_EXE` ordinarily identifies the interpreter, while a dirty `scripts/dispatch.py` can still claim clean commit and schema digests.

The plan relies on a “trusted clean-checkout/runtime-code attestation,” but defines no schema, artifact path, producer, trust root, creation timing, or mechanism proving that the measured files were the files executed by the PID/start identity. P2-06 produces such an attestation only for the evaluation controller; no step owns it for production dispatch. A self-issued or post-hoc checkout digest would not exclude dirty or substituted runtime code.

Thus a superficially conforming implementation could label a dirty checkout `post-phase-1`, and requirement 21 is not mechanically validatable.

Minimal amendment: define and assign, before P2-02, an attestation artifact/schema and independently trusted producer. It must bind boot ID, UID/unit/cgroup, PID/start identity, executable, actual runtime file closure, harness commit, schema/boundary digests, and invocation ID where applicable. State why the dispatcher or D5 worker cannot forge it and how execution from different bytes fails closed. Alternatively, explicitly keep production attempts at `unknown` until such an attestor exists.

3. The ordered specs contain unresolved circular acceptance dependencies.

Sections: §6 P2-01, P2-03, P2-02, P2-05, P2-08.

P2-03 requires representative datagrams to traverse SQLite and report projection before acceptance, but those projections are not implemented until P2-05. P2-02 depends on accepted P2-03 and repeats the same pre-authorization end-to-end requirement. Under the stated ordering, P2-05 cannot land early enough to satisfy either acceptance gate.

P2-01 also claims requirement 21 passes before the journald materializer, evaluation attestor, or A/B runner exists. Separately, P2-08 says unknown or mixed epoch rejects “before invocation,” while its per-run epoch requires an invocation-specific lifecycle record, PID/start identity, immutable invocation ID, and runtime attestation that can only be finalized during or after that invocation.

Minimal amendment:

- Move SQLite/report projection immediately after P2-01, before P2-03 and P2-02, or defer the full projection test to a later explicitly ordered integration gate.
- Scope P2-01 acceptance to the epoch contract and offline fixtures; assign full requirement 21 acceptance to the materializer, attestor, and runner specs.
- Split A/B validation into preflight validation of equal pinned boundary/configuration and post-run validation of each invocation’s epoch. Missing post-run capture must invalidate comparison publication, not be described as a pre-invocation rejection.

The other challenged resolutions cohere: event identity binds companion sources, extractor implementation, schemas, configuration, boundary, and semantic payload; changed projections cannot be silently suppressed without a cryptographic collision that the deterministic-content check detects. Exact-head checkpoints now support the stated truncation guarantee, and unacknowledged-tail recovery is defined without rewriting generations. The XOR counterbalancing formula is correct, and the statistical contract clearly separates ITT outcomes from the labelled eligible-task estimands, reports zero-pair exclusions, and suppresses efficiency direction under excessive differential missingness.

VERDICT: BLOCK
