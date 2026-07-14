Three blocking findings remain within the stop-rule.

1. **Attempt-level test selection can still pass vacuously.** R2 rejects an empty assertion set for an individual required test, but never requires the selected required-test set itself to be nonempty. Parent policy can select zero tests, producing no invocation records and an internally consistent empty aggregate. None of §8’s tests exercises this case. Require at least one selected parent-required test—and therefore at least one expected assertion—or produce `failed_test` before review.

2. **Direct-run commits can enter the installed trust base without the promised fresh attempt.** R1.14 requires a direct-run commit to undergo a fresh launcher-controlled attempt, but the installation record and §4.4 installation flow only verify the selected commit, tree, component digests, and operator authorization. They do not bind a post-bootstrap installed parent to a successful authoritative attempt, attestation, and review. In `evidence-only` mode, an externally merged direct-run commit could therefore receive a self-consistent installation record and become authoritative parent content. The poisoned-readmission test proves the intended path works, but does not test refusal of direct installation. Add a narrowly scoped installation-eligibility binding and a negative direct-install test; an explicitly digest-bound bootstrap exception can remain without adding the deferred activation state machine.

3. **Candidate-commit persistence has impossible ordering as written.** R4.1 requires launch persistence before candidate work, while §4.7 says the service persists the candidate commit “at launch.” The worker commit does not exist until candidate work finishes. Define two immutable stages: persist the criteria/spec/base/installation bindings before worker execution, then bind and seal `worker_commit` after its creation but before trusted tests and review. Verdict v4 must bind both stages.

These findings do not rely on any deferred activation, frozen-verifier, environment, log-tail, or evidence-sealing work.

VERDICT: BLOCK
