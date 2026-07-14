# Claude disposition — SOL round 3 of PLAN-004 rev4 (BLOCK, 3 findings — all executability, no security)

Event identity, checkpoints, counterbalancing, and the statistical contract are now explicitly
accepted as coherent. The 3 remaining defects are about EXECUTABILITY. All SUSTAINED:

1. **Durability rule unexecutable for some call sites → SUSTAIN.** Add the call-site table (record,
   transition, pre-existing durable artifact, barrier). Transitions with NO pre-existing durable
   artifact (concurrency marks, process-start) are redefined as post-transition OBSERVATION-ONLY
   records: emission after the scheduling/process transition completes; drop the false claim that
   canonical evidence exists for them. Explicitly forbid adding any new canonical write to dispatch.
2. **Runtime attestation has no producer → SUSTAIN, take the fallback.** No trusted attestor exists
   today and inventing one is a new trust-critical subsystem — out of Phase 2's scope. Therefore:
   **production attempts stay `epoch: unknown` until an attestor exists** (explicitly recorded as a
   residual + a named future work item). Journald producer metadata still distinguishes dispatcher
   from worker (keep), but it may NOT alone promote an attempt to post-phase-1. Golden/eval runs,
   where P2-06 DOES produce a controller attestation, may be `post-phase-1`. Consequence to state
   plainly: early trend/A-B value comes from the golden corpus, not from production history — which
   is where the operator's config-comparison question actually lives anyway.
3. **Circular acceptance dependencies → SUSTAIN.** Reorder: P2-01 (journal+collector) → P2-05
   (SQLite+report projection) → P2-03 (journald materializer) → P2-02 (dispatch emitter) → rest.
   Scope P2-01 acceptance to the epoch CONTRACT + offline fixtures. Split A/B epoch validation into
   preflight (equal pinned boundary/config) and post-run (per-invocation epoch); missing post-run
   capture invalidates PUBLICATION, not pre-invocation admission.
