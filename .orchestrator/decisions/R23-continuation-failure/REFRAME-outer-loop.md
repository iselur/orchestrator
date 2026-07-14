# REFRAME (operator, 2026-07-14): the timer IS the outer loop

My R23 assessment was mis-framed. I treated the continuation timer as infrastructure ("the unit
fired, the script had a bug, delete it, run tmux instead") and R20 as a separate literature review.
They are the same object: **the continuation mechanism is the orchestrator's OUTER LOOP**, and the
timer is only its clock. Judged as a loop — using the exact criteria R20 extracted — it failed on
every axis, and the fixed-interval clock was the least of it.

## The factory has two loops

- **Inner loop (well designed, exists):** spec → dispatch attempt → integrity/scope/test/review
  gates → remediation (bounded) → PR. Validator: deterministic gates + bound reviewer. State:
  per-attempt evidence. Stopping: remediation limits + escalation records. Incumbent: `integration`,
  never regressed by a failed attempt.
- **Outer loop (never designed):** what keeps the orchestrator itself working across usage windows,
  reboots, and detached-job completions — i.e. what makes the operator NOT have to restart it every
  5 hours. This is the loop that broke overnight.

## The outer loop against R20's own criteria

R20 found three indispensable loop facilities (real validator, durable state, stopping condition)
plus an applicability test. Our outer loop:

| Facility | Ours (deleted design) | Verdict |
|---|---|---|
| **Driver / clock** | Fixed 5h systemd timer | Wrong axis: fixed-interval, not event-driven. The real events are *usage-window reset* and *detached-job completion* — neither is a clock tick. |
| **Agent runtime (liveness)** | `claude -p` one-shot | **Fatal.** Ending a turn kills the process, so any detached work is orphaned; the agent could never receive the completion event it was waiting for. 9h of wall clock → ~12min of work. |
| **Validator** | **NONE** | The loop had no notion of "did this iteration produce anything?" A window that did nothing looked identical to a window that did work. Nothing detected 2 wasted windows. This is the deepest defect. |
| **Durable state / memory** | PENDING baton + NEXT.md prose | Crude: no record of hypothesis → outcome per iteration; each window re-derived context from scratch (`claude -p` without `--continue`). R20's "semantic ledger" critique of AutoResearch's untracked TSV applies to us verbatim. |
| **Stopping condition** | "PENDING file absent" | Under-specified: no budget exhaustion, no repeated-identical-failure circuit breaker, no operator-blocked state. (Ironically the gate worked — it correctly fired *because* PENDING existed — the loop just couldn't do anything once awake.) |
| **Incumbent / no-regression** | n/a | A failed window left orphaned processes and stale in-flight state rather than a clean incumbent. |

## The actual requirement (operator, restated)

"So I don't have to restart you every five hours when the box limits are hit." The outer loop must:

1. **Survive usage-limit exhaustion** and resume automatically at window reset — the limit is a
   normal, expected loop state, not a crash.
2. **Be event-driven, not tick-driven** — re-enter on (a) detached job completion, (b) usage-window
   reset, (c) operator input; the clock is a fallback heartbeat, not the primary driver.
3. **Keep a live agent** that can actually receive those events (a persistent session, not one-shot
   print mode).
4. **Validate its own progress** — every iteration must produce a durable artifact delta (plan
   revision, verdict, PR, ledger row, decision record). An iteration producing none is a FAILED
   iteration: surfaced, diagnosed, and repaired — never silently repeated. This is the missing
   validator that let the box idle all night.
5. **Remember across iterations** — what was attempted, what the outcome was, what is next, in
   durable form (not conversation memory, which dies with the process).
6. **Stop honestly** — work exhausted / operator-blocked / budget exhausted / repeated identical
   failure (circuit breaker) → surface to the operator instead of spinning.

## Consequence

The outer loop is a control-plane mechanism (it governs autonomous execution, budget, and when the
factory acts without a human). Per CLAUDE.md it gets planning-first + dual validation like anything
else — not a bash script written from the hip, which is exactly how the deleted one came to be.
The reuse candidates R20 ranked (semantic iteration ledger, gate-informed retry with an explicit
incumbent, eligibility test, stop policy) are not just for worker attempts — they are the
specification for THIS loop.

Plan: `PLAN-006` (outer loop / autonomous continuation), ledger R23. The deleted timer stays
deleted; nothing is reinstalled until the plan is authorized.
