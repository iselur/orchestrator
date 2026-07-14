# Claude challenge — PLAN-006 (the outer loop), draft of 2026-07-14

Verdict: **REVISE** — the design is strong and addresses every failure the forensics found. Four
objections, two blocking.

## What the draft gets right (do not lose in revision)

- Persistent interactive Claude with an **explicit session UUID** resumed every launch ("resume most
  recent" prohibited) — kills the `claude -p` one-shot defect at the root.
- **Detached jobs run as separate systemd units, not descendants of the Claude process**, and persist
  their manifest/event BEFORE attempting socket notification. This is the exact fix for the orphaned
  9-hour consult: a job completing while nobody is listening is not a lost job.
- The **progress validator** with an allowlist of durable delta types (plan revision, verdict,
  decision record, PR, ledger transition, spec/attempt record) and an explicit non-counting list
  (logs, pane transcripts, health samples, PENDING/NEXT, digest-only rewrites). This is the missing
  validator, and the non-counting list is what makes it honest.
- `WAITING_USAGE_RESET` as a **first-class state with a deadline parsed from already-observed
  output** and no polling loop — usage exhaustion as a normal loop state, exactly as required.
- Wedge detection requiring two consecutive stalled samples across pane bytes/CPU/hooks/job progress
  (matches the existing "busy-but-silent survives" health doctrine).

## O1 (BLOCKING) — the usage-limit classifier is a scraper, and it is on the critical path

§4.5 recognizes exhaustion via "a version-pinned ANSI-stripped classifier [that] recognizes a
complete known exhaustion record and reset instant." This parses vendor CLI output — the least
stable interface in the system. A CLI wording change silently breaks the ONE mechanism the operator
actually asked for ("so I don't have to restart you every five hours"), and the failure mode is the
loop going quiet, which is precisely the failure we are repairing. The draft's own mitigations
(negative fixtures, fail-closed on unknown protocol) protect against *spoofing*, not against
*upstream drift*.

Required amendment: add a **classifier-independent liveness fallback**. Concretely: if the agent is
not in a registered waiting state and no progress signal advances for N consecutive samples AND the
last turn ended without a valid Stop disposition, the controller performs a **cheap probe resume**
on a conservative schedule (e.g. attempt one resume per 30 minutes, bounded by budget) rather than
requiring the exhaustion record to have been parsed. Also: record the raw unparsed pane evidence to
`ATTENTION.json` and alert, so classifier drift surfaces loudly instead of as silence. The loop must
degrade to "retries a bit too often" — never to "sleeps forever because the wording changed."

## O2 (BLOCKING) — no budget ceiling on autonomous spend; §4.9's "STOPPED_BUDGET" has no defined meter

The state machine has `STOPPED_BUDGET` ("local grant exhausted") but the plan never defines what the
budget METER is, who decrements it, or what happens at 90%. A persistent self-driving agent with a
standing `--dangerously-skip-permissions` grant that iterates until "work exhausted" can burn an
entire usage window (and Codex quota, via job requests) on low-value iterations — the operator wakes
up to a spent budget and no PRs. This is the autonomous-spend analogue of the very problem being
fixed.

Required amendment: define the budget as **iterations and detached-job launches per grant window**
(both machine-countable without vendor APIs), with the grant naming both ceilings and an expiry;
decrement on iteration open and job launch; at exhaustion enter STOPPED_BUDGET and alert. Also add a
**value floor**: N consecutive iterations whose only durable delta is a plan revision on the SAME
plan id (i.e. the loop is polishing rather than shipping) trips the circuit breaker — this is the
machine-checkable form of the accretion failure the operator has already called out twice today.

## O3 — "Open questions: None for the design" is wrong; one real operator decision exists

The draft asserts no open questions, then lists execution approvals. But there IS a design-level
operator decision it silently made: **what the loop is allowed to do autonomously between operator
sessions.** The current answer (implied) is "everything the lanes allow, including dispatching
Codex workers and opening PRs." The operator may reasonably want a narrower night-mode: e.g. plans,
reviews, and research only — no worker dispatch, no PRs — until the loop has proven itself for a
week. Surface this as a real choice with a recommended default (recommend: **night-mode = full lanes
EXCEPT high-risk dispatch, which already needs a per-dispatch approval artifact the loop cannot
mint**), and make it a field in the activation grant rather than a code change.

## O4 — bwrap dependency is unstated in the runtime path

§4.11 routes around the broken codex sandbox, but the loop's detached-job kinds include codex
consults, which TODAY only work via the stdin/inlined-context method (proven repeatedly this
session; the repo-reading sandbox mode is dead on this host). State this as a hard precondition of
the job wrapper (job kind `codex-consult` MUST use the stdin form; the sandbox form is refused until
the host defect is fixed), so an implementer does not "fix" it back to the broken invocation.

## Process note

Control-plane + Critical (governs autonomous execution, budget, and when the factory acts without a
human) → after disposition, this gets a fresh-context adversarial review under the R24 stop-rule
before authorization.
