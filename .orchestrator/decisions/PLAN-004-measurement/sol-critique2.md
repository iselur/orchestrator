PLAN-004 revision 3 is materially improved, but it remains blocked by several internal contradictions and unbound evidence paths.

1. The `sd_journal_sendv` option does not establish critical-path independence.

Section 4.7 permits either a direct nonblocking datagram or `sd_journal_sendv` “with proven nonblocking datagram semantics.” Nothing in the plan defines that proof or constrains the library’s internal socket creation, buffering, fallback, allocation, retry, or file-descriptor behavior. The fault tests in P2-02 test observable outcomes but cannot prove that a higher-level library performed exactly one syscall, no fallback write, and no blocking operation.

There is also no call-site ordering requirement ensuring emission occurs only after the corresponding canonical transition is durable. An exception or cancellation between a completed transition and its canonical evidence write could therefore change the recorded outcome.

Minimal amendment:

- Remove `sd_journal_sendv` as an allowed implementation.
- Specify a direct `SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC` send using `MSG_DONTWAIT | MSG_NOSIGNAL`, a fixed local socket address, one bounded buffer, and no fallback.
- Require syscall tracing proving one attempted send and no file operations under every injected failure.
- Require each call site to occur only after the corresponding canonical evidence transition is durable, or move capture entirely out of process where that cannot be guaranteed.

Citations: §1 “Dispatch-side capture,” requirements 4, 18–19, §4.7, P2-02, §8.4.

2. Event identity does not bind the implementation that actually produces the payload.

The event ID binds the extractor-contract digest, but §4.3 binds Phase 1 function names, signatures, mappings, schemas, test vectors, and the contract generator. It does not explicitly bind the executable Phase 2 extraction and canonicalization code in `scripts/measure.py` or its semantic code closure. Consequently, two collector versions can emit different payloads for the same sources while producing the same `event_id`. Idempotence may then silently suppress the later projection, or restored generations may contain the same globally unique ID with different bodies.

The same issue affects epoch ancestry checks: their result can change with Git-object availability, yet the ancestry proof or failure is not identified as a source-set member.

Minimal amendment:

- Add a digest of the actual extractor/canonicalizer implementation closure to the extractor contract and verify it at collection time.
- Bind a deterministic semantic-payload digest into `event_id`, excluding only chain placement and explicitly nonsemantic observation metadata.
- Require duplicate event IDs to have byte-identical deterministic content; otherwise seal with an identity-collision error.
- Treat the Git ancestry proof, including the relevant commit objects or a trusted finalized attestation, as a contributing source.

Citations: requirements 9–11, §§4.3–4.4, “Semantic epoch” in §4.6, §4.10.

3. The semantic-epoch binding is forgeable or accidentally mislabelled.

Section 4.6 promotes an attempt to `post-phase-1` based on a materialized lifecycle record. Section 4.7 authenticates such a record only by `MESSAGE_ID`, boot ID/cursor, and raw schema. Client-supplied journald payload fields are assertions, not proof that the pinned dispatcher produced them. The plan does not require validation of trusted journald producer metadata or demonstrate that the worker boundary cannot inject an otherwise valid Phase 2 record.

A captured commit name also does not prove that the executing dispatcher bytes match that commit; a dirty or substituted worktree could self-report a valid descendant commit.

Minimal amendment:

- Validate trusted journald producer metadata such as UID, unit/cgroup, executable identity, PID/start identity, and boot ID.
- Add a canary proving a D5 worker cannot produce a record accepted as dispatcher-originated.
- Bind each evaluation record to an unpredictable ID predeclared in the immutable run manifest.
- Require a trusted clean-checkout/runtime-code attestation whose file digests match the claimed harness commit. Otherwise set the epoch to `unknown`.
- Include all provenance and attestation records in the event source set.

Citations: requirement 21, “Semantic epoch” in §4.6, “Post-hoc journal materialization” in §4.7, §§4.11 and 4.15.

4. The checkpoint design does not detect all clean truncation it claims to detect.

Checkpoints are periodic and required after “each append batch used for a report,” not after every successful append. A generation can therefore be cleanly truncated to a valid prefix within its uncheckpointed tail without any mismatch. That silently loses acknowledged observations while leaving a valid chain.

Additionally, a checkpoint cannot contain “the repository commit containing the checkpoint once committed.” The commit hash depends on the checkpoint’s contents, so embedding that same commit hash is circular and not executable.

Minimal amendment:

- Define collector success only after an immutable checkpoint candidate has been durably and atomically written for that exact append head.
- Specify append/checkpoint `fsync` ordering and recovery for a crash between the two.
- Narrow the truncation claim to heads protected by retained checkpoints and explicitly retain the recorded limitation for coordinated rollback of both journal and unanchored checkpoint.
- Remove the self-referential commit field. Record the containing commit externally, derive it from Git, or use a later anchor artifact that commits to the checkpoint digest.

Citations: requirements 6–8, §4.2, P2-01 acceptance, §7 “Complete-line truncation,” §8.3.

5. No implementation step clearly materializes lifecycle and concurrency records.

P2-01 implements projection contracts but says not to collect capture types before their producer/materializer specs land. P2-03 is specifically limited to Claude-envelope materialization. P2-02 subsequently emits lifecycle, concurrency, and Claude records but edits only `scripts/dispatch.py` and tests. No later step owns journald querying and immutable materialization for lifecycle or concurrency records.

Thus two of the four promised capture streams can be emitted but never become collector sources end to end.

Minimal amendment:

- Make P2-03 a generic journald materializer for lifecycle, concurrency, and Claude-envelope record classes, with fixtures for each.
- Keep the Claude archived-artifact join as an additional step over the materialized Claude records.
- Require an end-to-end test from each raw datagram class through immutable source materialization, journal event, and projection before P2-02 authorization.

Citations: §4.7, P2-01 implementation, P2-03 implementation and acceptance, P2-02 allowed paths.

6. The advertised AB/BA balancing does not follow from the scheduling formula.

Section 4.15 assigns each repeat an independent hash bit. For a task with two repeats, both bits may be equal, producing AB/AB or BA/BA and an order-count difference of two. With three repeats, all three may also be equal. This directly contradicts requirement 40 and P2-08’s deterministic counterbalancing acceptance criterion.

Minimal amendment:

```text
initial_bit = low_bit(sha256(run_id NUL task_id))
order_bit = initial_bit XOR ((repeat_index - 1) mod 2)
```

This guarantees 1/1 ordering for two repeats and 2/1 ordering for three while retaining deterministic task-level randomization.

Citations: requirement 40, §4.15 “Ordering,” P2-08 acceptance.

7. Hierarchical resampling is undefined when a task has no complete pair for a metric.

The plan permits metric-specific missingness and one-sided failures. Aggregate step 2 nevertheless requires sampling “complete paired repeats” within every sampled task. If a task has zero complete pairs for tokens, timing, or another nullable metric, that operation is undefined. Silently removing the task would change the estimand and could make a failing candidate appear cheaper.

Minimal amendment:

- Define the estimand and task weighting separately for every aggregate metric.
- Predeclare whether zero-complete-pair tasks make the metric non-estimable, are included through an explicit ITT value, or are excluded from a clearly labelled eligible-task estimand.
- Report scheduled and contributing task IDs/counts, zero-pair tasks, and arm-specific missingness alongside every interval.
- Prohibit directional efficiency conclusions when differential missingness exceeds a predeclared threshold.

Citations: requirements 37–38, §4.15 “Missing and failed runs” and “Aggregate statistics,” P2-08 acceptance.

There is also an execution-order contradiction: the Phase 1 precondition and §2.3 require the committed Phase 1 extractor contract before P2-01 can be authorized, while P2-01 says it will generate and commit that contract. The plan must choose one owner: either Phase 1 produces the immutable contract before Phase 2, with P2-01 only verifying or vendoring it, or P2-01 is permitted to create it under a narrower bootstrap precondition.

On the quoted evidence, golden isolation is otherwise coherently designed: both model roles cross D5, hidden material remains controller-side, fixture object closure is exact, and paid invocation is preceded by fail-closed canaries. The raw n=2–3 reporting and ITT score treatment are also appropriately cautious once the counterbalancing and zero-complete-pair defects above are corrected.

VERDICT: BLOCK
