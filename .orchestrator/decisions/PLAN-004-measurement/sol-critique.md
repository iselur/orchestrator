PLAN-004 should not be authorized. The overall projection direction is sound, and the corrected historical JSON pointers appear consistent with the cited artifacts, but several defects can still contaminate evidence, expose production state, and produce misleading A/B conclusions.

A repository-access caveat: the shell sandbox failed during initialization (`bwrap: loopback: Failed RTM_NEWADDR`) before any command ran. I therefore cannot honestly claim an independent byte-for-byte live read. The current-artifact assessment below is limited to the exact shapes quoted from the cited repository files; the blocking findings are independently present in PLAN-004 itself.

## Strongest counterargument to the architecture

The ledger is called canonical evidence even though it contains interpreted projections rather than raw observations. If authoritative attempt artifacts remain available, the ledger should itself be disposable. If those artifacts can disappear, the ledger is not sufficiently self-contained to recreate or challenge the interpretation. Moreover, its event identity omits some inputs to that interpretation, and a valid-line-boundary truncation is not detectable without an external checkpoint.

The minimal defensible formulation is:

- Existing attempt/evaluation artifacts remain canonical facts.
- The ledger is a canonical append-only observation journal, not canonical truth.
- Every derived event binds all source digests, the extractor/rule digest, schema digests, and semantic-boundary digest.
- Periodic externally stored ledger-head checkpoints detect truncation or deletion.
- Corruption starts a new hash-linked ledger generation; no in-place tail repair.
- Reports state exactly which ledger generation, checkpoint, source-set digest, and extractor digest they consumed.

SQLite and static HTML remain good disposable projections after those changes.

## Material findings

### 1. P2-02 puts measurement on the dispatch critical path

Section 4.10 and P2-02 place bounded serialization, file open/write/fsync operations, and possibly a Claude wrapper directly inside [dispatch.py](/home/val/orchestrator/scripts/dispatch.py). Catching exceptions does not make those operations off-path:

- Regular-file writes and `fsync` can block indefinitely.
- Capture can consume the last free blocks or inodes and cause a subsequent canonical result, review, or attestation write to fail.
- A wrapper can change signal propagation, buffering, cancellation, timeout, or process-group behavior even when arguments and final exit status appear equal.
- Capture and canonical evidence share the attempt filesystem, so ENOSPC isolation cannot be proven by exception handling.

This violates requirements 3 and 13 and the core non-critical-path condition.

Minimal amendment: dispatch may perform only a bounded, nonblocking datagram emission to an independently quota-bounded operator service, with `MSG_DONTWAIT`-equivalent behavior and no acknowledgement, retry, flush, or fsync. Production Claude capture should occur after the existing call, not through a wrapper. The capture spool must not share the quota needed for canonical evidence. Tests must include blocked I/O, quota exhaustion after partial writes, inode exhaustion, EINTR, short write, fd exhaustion, process cancellation, and helper absence—not merely injected Python exceptions.

### 2. Event identity can silently suppress semantically different evidence

The v1 identity uses only:

```text
source_path + source_sha256 + event_type
```

But multiple payloads depend on additional inputs:

- `attempt_result.duration_ms` depends on `launch.json`.
- `terminal_class` depends on `metrics_report.py`.
- `semantic_epoch` depends on the Phase 1 boundary.
- `gate_results` depends on attestation, review, result, and mapping inputs.
- Git projections depend on two commits, Git output, and classification configuration.
- Reportable capture streams and finding dispositions are appendable after terminal result.

Thus byte-identical `result.json` can legitimately yield a changed payload while retaining the same event ID. The collector will either silently retain the old interpretation or collide. No precise virtual source is specified for `gate_results`, `plan_deviation`, or several other multi-source events.

Appendable capture files create a second problem: each new source digest produces an event containing all prior records. Only `attempt_coverage` has an explicit “latest snapshot” projection rule, so lifecycle and disposition counts can be duplicated.

Minimal amendment:

- Define `source_set_sha256` from every contributing source digest.
- Bind `extractor_contract_sha256`, semantic-boundary digest, configuration digest, and derivation-rule version into event identity.
- Emit one event per capture/disposition record, or formally mark snapshots and select exactly one latest valid snapshot per logical source.
- Define supersession and active-error rules for every event family.
- Add fixtures where a companion artifact, extractor digest, or epoch boundary changes while the primary source bytes do not.

### 3. Semantic-epoch labeling can fabricate comparability

The plan derives epoch by comparing `/base_sha` and “evidence format” to the Phase 1 boundary. `/base_sha` identifies the worker’s target base; it does not necessarily prove which dispatcher checkout or uncommitted implementation produced the evidence. “Evidence format” is also not an exact decision rule.

This can label an attempt post-Phase-1 even though its harness semantics are unknown, enabling invalid trend or A/B mixing.

Minimal amendment: an attempt is post-Phase-1 only when a captured harness commit or signed attestation binds it to the pinned Phase 1 implementation and schema set. Otherwise the epoch is `unknown`, not inferred from artifact resemblance. Default trends and all A/B comparisons must reject `unknown` and mixed epochs mechanically.

### 4. Current extraction is improved, but PLAN-003 references are not yet fail-closed enough

The historical pointer corrections are appropriate:

- [launch.json](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/launch.json) uses `created`, `base_sha`, model/effort, isolation, scope, and spec-digest vocabulary.
- [result.json](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/result.json) uses `status`, `error_class`, `finished`, merge fields, and worker commit—not fictional nested gate structures.
- [review.json](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/review.json) is correctly treated as historical v3 with `/verdict`, legacy findings, and no rounds.
- [raw/events.jsonl](/home/val/orchestrator/.orchestrator/attempts/SPEC-015/1/raw/events.jsonl) is correctly restricted to `turn.completed` usage paths and `/item/type`.
- [SPEC-002/2](/home/val/orchestrator/.orchestrator/attempts/SPEC-002/2) is correctly handled as incomplete inventory.

The weakness is the future contract. [PLAN-003](/home/val/orchestrator/.orchestrator/plans/PLAN-003.md), [verdict.schema.json](/home/val/orchestrator/scripts/verdict.schema.json), and [metrics_report.py](/home/val/orchestrator/scripts/metrics_report.py) are to be pinned later, but “reuse or prove fixture-for-fixture equivalence” is insufficient. A finite fixture set does not prove behavior for every valid status/error-class combination or future enum member. Several event types also lack an exact source/payload contract: `remediation_summary`, `escalation`, `plan_record`, `decision_record`, `plan_deviation`, and `matrix_result`.

Minimal amendment: P2-01 must consume a generated, committed Phase 1 extractor contract containing exact function names/signatures, output schemas, complete status/error-class mapping tables, schema digests, and exhaustive valid-enum tests. Collection must verify those digests on every run. Any unsupported value must produce `measurement_error`, never fall through to `unknown` unless the contract explicitly permits it.

### 5. Hostile evidence can still execute in the report or escape bounds

“Exact JSON embedded in HTML” plus “never `innerHTML`” does not prevent a payload containing `</script>` from terminating an inline script element before JavaScript parsing. Text-node insertion happens too late.

Additional gaps include:

- No per-string, per-array, per-line, subprocess-output, event-size, or total-report bound is specified.
- Git permits unusual and non-UTF-8 path bytes; the encoding or rejection contract is absent.
- `scripts/measure disposition --attempt <path>` has no stated `openat2`/dirfd containment rule.
- Local evidence-link generation needs URL-scheme rejection and realpath containment, not only HTML escaping.
- Error messages themselves can contain attacker-controlled values.

Minimal amendment: embed report data as base64 or escape `<`, `>`, `&`, U+2028, and U+2029 before placement in an inert data element. Add explicit bounds at every aggregation layer. Represent non-UTF-8 Git paths losslessly or fail the affected projection explicitly. Resolve writable attempt paths beneath a pre-opened attempts-directory fd with symlink/traversal rejection. Test `</script>`, `javascript:`, control characters, massive arrays, huge Git diffs, and non-UTF-8 filenames.

### 6. Ledger crash recovery is not append-only and cannot detect clean truncation

A partial final line causes permanent refusal until “manual trailing-byte repair,” which rewrites the canonical ledger. A truncation at a complete-line boundary remains schema-valid and is not detectable without an external checkpoint.

The exclusive `flock` is adequate for two cooperating collectors on one local filesystem, but it does not address crash consistency or deletion.

Minimal amendment: never repair a ledger generation in place. Seal the damaged generation, preserve its hash, and create a new generation with an explicit predecessor hash. Store signed or tracked head checkpoints periodically. Test death after every byte boundary, complete-line truncation, fsync failure after visible write, and concurrent first-run lock creation.

### 7. Golden isolation is declarative, not enforceable

`production_prs: false`, “reject any production remote,” and a unique fixture branch do not prevent a model process from:

- Running `gh`, `git push`, `ssh`, or direct network commands.
- Reading the original `eval/golden/v1` tree, hidden checks, or labels.
- Inheriting operator environment variables, SSH agents, Git configuration, or credentials.
- Accessing production repository/worktree paths.
- Discovering hidden objects or extra refs embedded in a Git bundle.

The scorer’s exact harness entrypoint is also unspecified. P2-06 does not modify dispatch, so it is unclear how the real gate chain is exercised without production behavior.

Minimal amendment: define a sealed evaluation execution profile using the existing worker UID/isolation boundary, an empty HOME, scrubbed environment, no credential/agent fds, no production mounts, no production remotes, and denied tool egress. The reviewer process must receive the same isolation treatment. Validate that each bundle exposes exactly the intended ref/object closure and contains no oracle, hidden-check, label, or manifest blobs. Production-side-effect canaries must fail closed before any paid invocation.

### 8. Dataset digest and holdout integrity are incomplete

The example hashes the bundle and oracle scripts, but not explicitly:

- `manifest.json`
- `spec.yaml`
- dataset index and ordering
- file modes and symlink policy
- the complete fixture object closure
- scorer/rubric schema and trusted scoring implementation

The “exact manifest shape” is also internally invalid: each rubric bucket declares nonzero points while `criteria` is empty, contradicting the requirement that criteria sum to the bucket total.

Holdout enforcement is not specified. `holdout_eligible: true` does not identify current holdouts, define rotation, prevent routine matrices from selecting them, or prevent routine reports from exposing results. Since all tasks and hidden scripts are in the repository, a harness author can inspect them.

Minimal amendment: define a canonical Merkle-style dataset digest over every manifest, spec, fixture object, executable mode, oracle, hidden check, schema, scorer digest, and ordered task list. Fill real rubric criteria or make the example explicitly non-normative. Add an operator-owned signed holdout registry, rotation epoch, selection rule, and matrix-schema rejection of holdouts in routine mode. Effective holdouts need a sealed/private task pool, not merely unpublished scores for public tasks.

### 9. Rubric points are not necessarily bound to independent oracles

Stable criterion IDs and fixed bucket totals prevent point shifting, but not rubric gaming. The example’s reviewer matcher awards on required terms such as `symlink` and `prefix`; a reviewer can repeat those words without identifying the planted defect. Gate and honesty points can likewise be based on self-produced evidence unless assertion kinds are tightly restricted.

Minimal amendment: enumerate allowed assertion kinds and their trusted evidence sources. Functional points must come from hidden-oracle results; scope points from independently computed diffs; gate points from attested gate evidence; honesty points from terminal behavior versus oracle truth; reviewer points from a structured affected-path/rule/outcome matcher or blinded adjudication. Keyword presence alone cannot award defect-catch points.

### 10. Reviewer-value fork prevention is not enforceable

Tasks 07/08/10/11 share manifest metadata, which is the right direction, but the manifest lacks what audit action 7 needs for a controlled reviewer intervention:

- Shared pre-review worker artifact/run digest.
- Exact reviewer-on/off intervention.
- Arm-specific expected gate and scoring behavior.
- Common evaluator/scorer digest.
- Post-review remediation or terminal outcome.
- Proof that both arms begin from identical worker output rather than separate stochastic worker runs.

P2-07’s allowed paths include no audit-action-7 consumer, so “selects probes by manifest query and has no copied definitions” is not mechanically established against [PLAN-003](/home/val/orchestrator/.orchestrator/plans/PLAN-003.md).

Minimal amendment: define a reviewer experiment manifest that freezes one worker artifact and forks only after that digest. Record both arm manifests, intervention, evaluator digest, outcomes, and shared probe/fixture/label digests. Add the actual audit-action-7 consumer to allowed paths and test that it resolves these manifests directly.

### 11. Section 4.9 permits statistically dishonest deltas

Several independent problems remain:

- Per-task paired-bootstrap “95% confidence” intervals with two or three pairs are extremely discrete and should not be presented as inferential confidence intervals.
- The resampling unit, draw count, seed derivation, missing-pair handling, and aggregate hierarchy are unspecified.
- `baseline_n` and `candidate_n` omit `paired_n`; one-sided missing results can disappear.
- Explicit run errors need not emit a `golden_score`, enabling survivorship bias.
- Percentage delta remains allowed for arbitrarily small positive baselines.
- The shown schedule always runs baseline before candidate, creating temporal, caching, quota, and service-load bias.
- “Exactly one declared factor” does not prove all causal inputs match. A differing `harness_commit` can also change the evaluator, scorer, isolation, or hidden-data exposure.
- The example’s 58-run budget is not derivable without identifying which two holdouts were removed; all prescribed repeats total 33 runs per arm, or 66 paired runs.

Minimal amendment:

- Report raw paired differences for per-task n=2–3 and label their range/descriptive bootstrap distribution, not a 95% confidence interval.
- For aggregate uncertainty, predeclare hierarchical resampling by task then paired repeat, with deterministic seed, draw count, and complete-case rules.
- Add `scheduled_pairs`, `paired_n`, one-sided-missing counts, and reasons.
- Use intent-to-treat handling: every scheduled failure remains in terminal-disagreement and safety denominators, with a predeclared scoring rule.
- Make percentage delta null for bounded scores, counts, rates, and baselines below a declared meaningful threshold.
- Counterbalance AB/BA order deterministically within task/repeat.
- Freeze one trusted runner/scorer/isolation/oracle implementation outside both compared harness commits.
- Fully resolve and hash every causal configuration field; compare those hashes rather than trusting `isolated_factor`.
- Record holdout IDs and make the computed run total agree with the schedule.

### 12. Ordering, fresh-box behavior, and reproducibility are unresolved

- P2-02 is ordered before P2-03 but may depend on P2-03’s finalized interface. “Hold authorization” is not an executable dependency order.
- Raw capture schemas are described as schema-validated but no raw-schema files are owned by P2-01/P2-02.
- P2-08 says it “emits” ledger events, conflicting with the rule that evaluation evidence is collected as a projection. The runner must not append the ledger.
- A fresh clone lacks the local ledger, gitignored raw attempt streams, raw evaluation results, timer state, and possibly concrete pinned artifacts. Bootstrap behavior is undefined.
- Requirement 15 demands byte-identical `report.json`, while §4.7 gives it a clock-derived `generated_at` when `--as-of` is omitted. Both cannot be true.
- Deterministic float encoding, row ordering, and SQLite JSON capability checks are unspecified.

Minimal amendment: reorder P2-03 before P2-02 or forbid wrapper integration; add explicit raw-capture schemas before either writer; require the matrix runner to write finalized source artifacts only; specify `measure doctor/bootstrap` behavior on a fresh clone; and make report `as_of` derive deterministically from the ledger unless explicitly supplied. Put any wall-clock build timestamp only in noncanonical HTML metadata. Define canonical JSON ordering and numeric serialization.

The plan has a solid separation goal, good null/coverage discipline, and materially improved historical extraction. Those strengths do not cure the synchronous capture dependency, incomplete semantic identity, unenforced golden isolation, and biased comparison rules.

VERDICT: BLOCK
