# R23 — Why the overnight continuation "did nothing" (2026-07-14)

## What actually happened (evidence)

The timer infrastructure WORKED mechanically. `orchestrator-continue.timer` fired on schedule
(00:36 and 05:36 UTC — journalctl), the gate correctly saw the PENDING baton, and both runs
launched `claude -p`. Both exited 0.

**Failure layer 1 — one-shot print mode treated as a living session (the fatal design flaw).**
`claude -p` is a single turn: the process EXITS the moment the model ends its turn. Both overnight
sessions launched *detached* Codex consults and then ended their turn "to wait for background
notifications" (verbatim in `continue-logs/20260714T053621Z.log`: "I'll end this turn and resume
when the background tasks notify me"). In print mode those notifications can never arrive — the
process is already dead. Result: 9 hours of wall clock bought ~12 minutes of agent time (7 min +
5 min), and every detached job was orphaned until the next 5-hour window.

**Failure layer 2 — the detached consults themselves died on the box's broken Codex sandbox.**
`decisions/PLAN-005-isolation-failopen/response.attempt1.md` and `response.attempt2.md` are both
0 bytes with ~36KB of stderr: the `bwrap: loopback: Failed RTM_NEWADDR` failure (Ubuntu 24.04
`apparmor_restrict_unprivileged_userns` blocks codex's sandbox netns setup). So even the one step
each window queued produced nothing to process.

**Failure layer 3 — no event-driven re-entry.** Nothing watched for "detached job finished/died";
the only re-entry was the next 5h window, which started a FRESH `claude -p` with no conversation
context (the script never used `--continue`), re-paying orientation cost every time.

Net effect, as the operator observed: the box was idle all night while a dead consult sat orphaned.

## Actions taken (operator-ordered)

- `orchestrator-continue.timer` + `.service` disabled, unit files and wants-symlink deleted,
  daemon reloaded. Verified: no orchestrator timers remain.
- `continue-session.sh` and `continue-logs/` KEPT as evidence and design reference (gitignored).
- The orphaned PLAN-005 SOL consult relaunched (attempt 3) via the stdin method that works on this
  box despite the bwrap defect.

## Proposed replacement (operator decision)

**Option A — RECOMMENDED: persistent tmux-resident session + script-only watchdog.**
Run the orchestrator as a LONG-LIVED interactive `claude` session inside tmux — the exact mode that
ran today's entire PLAN-003/004 pipeline, provably receiving background-task notifications and
self-continuing. A 10-minute systemd watchdog timer runs a bash-only check (zero quota):
- tmux session absent AND PENDING baton exists → create session, send the resume prompt;
- claude process exited inside tmux → relaunch with `--continue` (context preserved);
- usage-limit marker in the pane → leave it; the next check retries after reset (self-healing —
  no operator restarts).
Pros: notifications work (no orphaned consults); persistent context; survives window exhaustion;
operator can `tmux attach` any time to watch or steer. Cons: a persistent
`--dangerously-skip-permissions` session (same trust posture as the deleted design); needs the
HALT-file killswitch honored in the resume prompt (kept).

**Option B — minimal: keep timers but fix the two fatal bugs.** `claude -p --continue` each window
(resume the same conversation) + a binding prompt rule: "You are one-shot; ending your turn kills
the process. NEVER end the turn while detached work is in flight — babysit it with bounded
sleep/check loops inside the turn." Plus a 15-min script-only watcher that fires the service early
when a consult output file appears. Cheaper, still turn-scoped, weaker.

**Option C — cloud routines (`/schedule`)** for the CLOUD-SAFE items only (ACTION-PLAN A–E lane).
Cannot run the on-box trust-critical lane (systemd, isolation drills), so it complements but cannot
replace A/B.

**Independent of the choice:** the bwrap/AppArmor defect should be fixed or permanently worked
around — it killed every consult the windows launched. Fix candidates: (a)
`sysctl kernel.apparmor_restrict_unprivileged_userns=0` (sudo; loosens a host hardening knob —
operator decision), or (b) standardize all codex invocations on the stdin/inlined-context pattern
that works today (current workaround; costs repo-read ability in consults).
