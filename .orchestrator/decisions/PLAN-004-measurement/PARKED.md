# PLAN-004 — PARKED at revision 6 (2026-07-14)

**Status:** parked, NOT abandoned. Not authorized. No further review rounds until the plans ahead of
it in the R24 sequence (PLAN-005 → PLAN-006 → PLAN-003) have SHIPPED.

## Why parked rather than iterated

Round-3 review (stop-rule applied) returned 3 blocking findings. The first is not a patchable defect
but a SCOPE decision:

> Any in-process emitter is on the dispatch critical path. SOCK_NONBLOCK prevents waiting for buffer
> space; it does not remove CPU work, socket setup, page faults, exception handling, or syscall
> completion from the critical path. Cancellation is irreconcilable: swallowing it inside the emitter
> changes dispatch cancellation behaviour; propagating it lets measurement abort dispatch.

The honest options are:
- **(A) Restate the requirement honestly:** measurement provides BOUNDED FAIL-OPEN instrumentation,
  not zero-impact. Accept a small, characterized cost inside dispatch. (What the plan actually
  delivers today.)
- **(B) Zero dispatch code changes at all:** drop the four capture points (P2-02) entirely. Derive
  everything post-hoc from existing evidence + the systemd journal. Accept the coverage gaps
  (process lifecycle, concurrency marks, Claude envelopes) as UNKNOWN rather than instrumenting.
  This is the anti-accretion choice and needs no trust-critical dispatch change at all.

**Claude's recommendation: (B) for v1.** It removes the only high-assurance spec from Phase 2,
removes the whole controversy, and still delivers the read-only projection, the report, the golden
dataset, and the A/B runner — which is where the operator's real question ("is this harness best, on
data?") lives anyway, especially now that production attempts stay `epoch: unknown` (rev5 finding).

## Additional blocking findings recorded for whoever resumes this
2. Implementation order retains a controller-attestation dependency cycle (P2-06 attestation
   consumed before it exists).
3. (see sol-critique5.md)

## Why now is the wrong time to decide
The R25 architecture review (dual-vendor, in flight) may reshape what measurement should even BE for
a one-person company. Deciding Phase 2's shape before that lands would be planning-for-planning's
sake — the exact failure the operator has flagged twice.

**Resume trigger:** PLAN-005, PLAN-006, and PLAN-003 shipped, AND the R25 review has landed.
