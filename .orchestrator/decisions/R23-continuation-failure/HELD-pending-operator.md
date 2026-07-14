# PLAN-006 (outer loop) — HELD at revision 3, pending operator decision (2026-07-14)

**Not authorized. No further review round launched.**

## Why held

rev3 correctly fixed all four safety-material blockers (B1 wedged detached job — the nine-hour orphan
in new clothes; B2 heartbeat that only detected instead of recovering; B3 iteration meter that bounded
turns, not spend; B4 evadable value floor). Those fixes are RIGHT and must survive into whatever ships.

But the plan grew 1,212 → 1,728 lines to make them. The R25 dual-vendor architecture review (delivered
to the operator today) says the outer-loop design is over-built in a specific, structural way:

> "Do not make a tmux-held Claude process the durable brain. Persist the session and workflow; restart
> the reasoning process freely." (Codex/SOL, citing Cursor's Temporal migration + Anthropic Managed
> Agents as the production pattern.)

> "An iteration that mutated no lifecycle object is a failed iteration — that is precisely the missing
> validator PLAN-006 spends 1,212 lines circling." (Claude repo review.)

Both reviewers say the same thing: the loop's complexity is a symptom of having no LIFECYCLE SPINE.
With one durable object chain (Idea → Decision → Ticket → Attempt → Change → Release → Service →
Incident), the progress validator becomes trivial, the state machine shrinks, and the "durable brain"
problem disappears because the brain becomes disposable.

## What MUST survive into any replacement (the load-bearing findings, in order of value)

1. **Detached jobs are separate systemd units that persist their result BEFORE notifying.** This alone
   fixes the observed failure (a Codex consult sat dead for 9h because a `claude -p` turn ended).
2. **A job whose EVERY progress signal is flat across consecutive samples → alert → bounded stop.**
   Without this, a wedged job recreates the silent failure. (No minute-scale timeout: an advancing
   long consult survives.)
3. **The agent runtime must be able to RECEIVE completion events** — never one-shot print mode.
4. **A real progress validator:** an iteration producing no durable delta is a FAILED iteration,
   surfaced. (With a spine: "mutated no lifecycle object".)
5. **A spend ceiling, not a turn ceiling:** every model-bearing action maps to a reserved admission;
   no recursive Claude invocation from the agent namespace; finite wall-clock per iteration.
6. **Value floor that only EXTERNALLY MEANINGFUL transitions reset** (merged PR, terminal gate
   outcome, ledger row closing) — self-produced plans/verdicts do not reset it.
7. **Usage exhaustion is a normal state with a classifier-INDEPENDENT fallback** (never sleep forever
   because vendor wording changed).
8. **Heartbeat that RECOVERS the controller**, not merely detects its death.

## Operator decision (open, same fork as PLAN-003)
- **(A) R25 path:** build the lifecycle spine first, then a much smaller controller over it carrying
  the 8 findings above.
- **(B) Continue:** review + authorize rev3 as drafted (1,728 lines).

Recommendation: (A). The 8 findings are what matter; the 1,728 lines are not.
