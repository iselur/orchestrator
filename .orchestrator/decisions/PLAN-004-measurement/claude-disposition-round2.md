# Claude disposition — SOL critique round 2 of PLAN-004 rev3 (BLOCK, 7 findings + 1 contradiction)

Golden isolation and small-n statistics fundamentals explicitly accepted. ALL SUSTAINED:
1. Datagram spec: remove sd_journal_sendv; direct SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC +
   MSG_DONTWAIT|MSG_NOSIGNAL, fixed address, one bounded buffer, no fallback; syscall-trace test;
   emission only after the canonical transition is durable.
2. Event identity binds the extractor/canonicalizer implementation-closure digest + a deterministic
   semantic-payload digest; duplicate IDs must be byte-identical else identity-collision seal; git
   ancestry proof joins the source set.
3. Epoch: validate journald producer metadata (UID, unit/cgroup, exe, PID+start, boot ID); D5
   worker-forgery canary; eval records bind to predeclared run-manifest IDs; clean-checkout/runtime
   attestation required else epoch=unknown.
4. Checkpoint per append head (collector success = durable checkpoint written); fsync ordering +
   crash recovery; truncation claim narrowed to checkpointed heads; remove self-referential commit
   field (external anchor instead).
5. P2-03 becomes the generic journald materializer (lifecycle, concurrency, Claude-envelope) with
   per-class fixtures + end-to-end tests before P2-02 authorization.
6. Counterbalancing: adopt the exact XOR formula (initial_bit XOR (repeat_index-1 mod 2)).
7. Per-metric estimand + zero-complete-pair predeclared handling; scheduled/contributing task
   accounting; directional-conclusion prohibition above a differential-missingness threshold.
Contradiction: Phase 1 owns the committed extractor contract (produced as part of Phase 1's
Dispatch 5 completion evidence); P2-01 only verifies/vendors it. (Matches PLAN-003's completion
reconciliation — no bootstrap exception needed.)
