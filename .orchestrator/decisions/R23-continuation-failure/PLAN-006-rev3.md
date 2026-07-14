---
id: PLAN-006
created: 2026-07-14
author: OpenAI Codex (GPT-5.6)
status: challenged
ledger_ref: R23
lane: control-plane
revision: 3
supersedes: PLAN-006 revision 2
---

# PLAN-006 — Event-driven, durable outer loop for autonomous continuation

> **Brief-caliber standard (operator, 2026-07-13):** every plan artifact must reach the depth of the
> original SETUP-BRIEF — a standalone document detailed enough that an agent can execute it
> autonomously with NO further clarification. Not a bullet sketch. If a section is genuinely N/A,
> write “N/A because …”. Codex drafts to this template; Claude challenges + authorizes; both then
> follow it.

## 1. Decision & non-goals

Implement the orchestrator’s outer loop as a hybrid, event-driven control plane. A deterministic,
quota-free Python controller runs continuously as a hardened systemd user service and owns the state
machine, durable event spool, append-only iteration ledger, machine-countable grant budgets,
validation, circuit breakers, liveness recovery, and privileged capability broker. A persistent
interactive Claude CLI process runs in an isolated tmux PTY as a separately hardened,
controller-managed service; tmux supplies interactivity and operator visibility but is not the
supervisor.

The controller delivers durable events only while the Claude prompt is known idle, keeps an
iteration open across detached work and recognized usage waits subject to its finite admitted-
iteration wall-clock ceiling, and resumes the same explicit Claude session after a CLI exit or
reboot. “Resume most recent” is prohibited.

Detached jobs run in independent systemd units and atomically publish terminal manifests and
completion events before notification. They have a conservative, signal-based liveness protocol:
unit state, CPU time, raw stream/output growth, and progress-file mtimes are sampled at a default
fifteen-minute interval. All signals remaining flat across two consecutive samples produces
`JOB_OVERDUE` and an operator-visible alert. Four consecutive stalled windows by default produce
`STOPPED_JOB_WEDGE`, preserve evidence, and terminate the affected unit. This is not a minute-scale
timeout: a `codex-consult` job with any advancing CPU, stream, output, or declared progress signal
survives indefinitely under the liveness rule.

Usage exhaustion is a persisted `WAITING_USAGE_RESET` state with a deadline derived from
already-observed CLI output, never a crash and never a periodic quota poll.

The usage classifier is an optimization, not a single point of liveness. If upstream wording changes
and no known exhaustion record matches, the controller captures the raw unparsed pane evidence,
surfaces the mismatch in `ATTENTION.json`, and performs bounded exact-session probe resumes on a
conservative schedule. Probe resumes consume ordinary iteration and model-invocation budget.
Classifier drift therefore degrades operation to a few potentially unnecessary retries followed by
a loud stop, never an unbounded silent sleep.

The heartbeat is an independent recovery authority, not merely a detector. It writes alerts and a
recovery journal through a controller-independent path and lock, terminates a stale controller
cgroup, starts or restarts the controller, and verifies that the controller lease advances. After a
bounded number of failed recoveries it creates a durable loud-stop sentinel, stops the outer agent
and registered jobs, and persists operator-visible evidence without depending on the controller.
The controller service uses `Restart=always`.

Autonomous spend is bounded by three machine-countable meters per activation-grant window:

1. iterations opened;
2. detached-job launches admitted; and
3. model invocations admitted.

Every model-bearing action maps to a named, durably reserved model-invocation admission. A worker
dispatch also reserves a detached-job unit before the installed dispatcher may launch its worker.
`codex-consult` and every other model-bearing detached job reserve both a detached-job unit and a
model-invocation unit. Initial Claude prompt delivery, exact-session resume, recognized-reset resume,
and liveness-probe resume each reserve a model-invocation unit. Non-model broker operations may not
launch a model.

All ceilings and the window expiry are named in the activation grant. Counters are reserved
atomically before the corresponding action, persist across restart/reboot, warn before exhaustion,
and cannot be replenished by the model. Reservation UUIDs make reconciliation idempotent, while an
uncertain invocation is conservatively counted and may not be replayed under the same reservation.

An admitted iteration has a generous finite wall-clock ceiling, defaulting to four hours. At its
deadline the Claude cgroup is terminated, the iteration is finalized with
`ITERATION_WALL_CLOCK_EXCEEDED`, and durable detached-job or reset state remains independently
reconcilable. The deadline does not impose a timeout on an independently progressing
`codex-consult`. Exact-session resumptions are additionally bounded per iteration and separately
charged to the model-invocation meter.

The agent namespace cannot recursively invoke Claude, Codex, worker model entrypoints, or equivalent
provider clients. The controller-owned initial Claude launch uses an installed absolute entrypoint;
the running agent’s executable view and `PATH` exclude all model entrypoints, alternate package
entrypoints, and repository copies. Activation requires negative tests proving direct, absolute,
symlinked, and runtime-mediated recursive invocation attempts fail. If this enforcement cannot be
proved for the installed CLI, activation is blocked rather than falling back to an unmetered path.

A value-floor circuit breaker stops plan accretion. It maintains a durable per-plan count of
same-plan revisions since the last externally meaningful, independently validated transition.
Revisions of a plan count toward that plan’s floor even when their iteration also emits a `VERDICT`,
`DECISION_RECORD`, failure, recovery record, or revision of another plan. Only a merged PR, an
attempt reaching a terminal gate outcome, a request-ledger row reaching `done` or `blocked`, or an
independently receipted operator-visible deliverable resets the applicable floor. Self-produced
verdicts and decision records about the loop’s own plans do not reset it.

Every completed iteration passes through an independent allowlisted artifact-delta validator before
it can be called successful.

Activation is fail-closed, uses a separately installed authorized controller rather than mutable
candidate code, and remains subject to HALT, autonomy-mode, high-risk approval, branch, review, and
merge invariants.

Non-goals:

1. This plan does not change the worker inner loop, remediation policy, gate meanings, reviewer
   independence, branch protections, or integration-to-main promotion.
2. It does not make an iteration-ledger entry proof that work is correct. The outer validator proves
   durable progress; existing specs, gates, independent review, CI, and human authorization prove
   admissibility.
3. It does not autonomously merge trust-critical work, weaken high-risk approval, touch remote main,
   or grant the model direct GitHub, SSH, Codex, sudo, or user-systemd credentials.
4. It does not restore the deleted five-hour timer or use periodic model invocation as the ordinary
   driver. A ten-minute local heartbeat is zero-quota health sampling and controller recovery. The
   only scheduled model invocation is the bounded classifier-independent recovery probe after an
   unclassified liveness anomaly.
5. It does not depend on changing
   `kernel.apparmor_restrict_unprivileged_userns`. Codex consultations route around the broken bwrap
   path with complete stdin context inside an external systemd isolation boundary.
6. It does not allow `codex-consult` to use repository-reading sandbox mode on this host. That form
   is refused until the host defect producing
   `bwrap: loopback: Failed RTM_NEWADDR` is separately fixed and reauthorized.
7. It does not self-activate. Challenge, dual validation, authorization, installation, and staged
   operator-approved activation remain mandatory.
8. It does not infer how much autonomous work the operator permits. The operator chooses an
   `autonomy_mode` in each activation grant.

## 2. Current-state evidence (facts, with citations)

### Observed facts

1. The repository already has a bounded inner loop: schema-approved specs dispatch attempts through
   integrity, scope, test, and review gates; remediation is bounded; attempts retain evidence;
   stale-base work is refused; and main promotion is human-only. See AGENTS.md, “What this repo is,”
   and CLAUDE.md, “Definition of done,” “Remediation + integration,” and “Hard invariants.”
2. The prior continuation mechanism was a five-hour systemd user timer invoking
   `continue-session.sh`, which ran one-shot `claude -p` under a five-hour timeout. Its continuation
   decision was a PENDING baton or live-attempt scan. See the deleted script supplied in R23.
3. The timer fired at 00:36 and 05:36 UTC and both `claude -p` processes exited zero. Timer delivery
   therefore was not the primary failure. See the operator-supplied R23 forensics and journal
   observations.
4. The 05:36 run said it would end the turn and resume on background notifications, but `claude -p`
   exited with the turn and could not receive them. See
   `.orchestrator/continue-logs/20260714T053621Z.log` as quoted by the R23 forensics. Roughly nine
   hours produced about twelve minutes of agent work.
5. PLAN-005 Codex consultations produced empty response files and about 36 KB of stderr containing
   `bwrap: loopback: Failed RTM_NEWADDR`. See
   `.orchestrator/decisions/PLAN-005-isolation-failopen/response.attempt1.md`,
   `response.attempt2.md`, and their sibling stderr evidence identified in R23.
6. The deleted service had no explicit Claude session identifier, no durable hypothesis/outcome
   ledger, no detached-completion event consumer, and no artifact-delta validator. A zero exit was
   indistinguishable from useful work. See the deleted `continue-session.sh` and the R23 reframe
   table.
7. The timer/service were disabled and deleted; the script and logs were retained as evidence. They
   must not be revived. See R23, “Actions taken.”
8. Existing policy treats worker usage exhaustion as interrupted, not failed; requires a fresh worker
   attempt rather than resuming a partially modified worktree; and prohibits minute-scale SOL
   timeouts. See CLAUDE.md, “Quota / degradation policy,” and AGENTS.md, “Consulting Codex SOL.”
9. HALT is the global kill switch; high-risk dispatches require per-attempt approval; candidate
   trust-boundary code may not validate or activate itself; and main promotion is human-only. See
   CLAUDE.md, “Autonomy level,” “Execution split,” “Remediation + integration,” and “Hard
   invariants.”
10. The target is Ubuntu 24.04 with `systemd --user`, tmux, Claude CLI, and Codex CLI installed. The
    bwrap failure is an observed host defect at the user-namespace/AppArmor boundary.
11. The working Codex route used complete stdin/inlined context rather than repository reading.
    Repository-reading sandbox invocation is not a viable fallback on the current host.

### Assumptions that must become measured preconditions

1. The installed Claude CLI supports an interactive PTY, explicit session identity or exact-session
   resume, and a Stop hook. Implementation must record `claude --version` and pass disposable
   hook/session-resume tests. It must not silently substitute “most recent conversation.”
2. Known installed-CLI usage output can be captured as sanitized fixtures for the primary
   classifier. A parser mismatch is not permitted to create an indefinite waiting state; the
   classifier-independent recovery protocol in §4.5 applies to all unmatched output.
3. The required systemd user hardening directives work on Ubuntu 24.04.
   `systemd-analyze verify` and negative access tests must prove the effective boundary; unsupported
   directives block activation.
4. The user manager starts after reboot without login. `loginctl show-user` must report `Linger=yes`
   before the reboot drill. Enabling linger is a one-time privileged operator action.
5. The exact working stdin/inlined-context Codex argv can be recovered and reproduced inside the
   external hardened job unit.
6. As a hard precondition, job kind `codex-consult` MUST use that stdin/inlined-context invocation.
   The wrapper MUST refuse repository-reading sandbox form while the host exhibits
   `bwrap: loopback: Failed RTM_NEWADDR`. Absence of a reproducible stdin form blocks activation of
   `codex-consult`; it does not authorize weakening AppArmor or substituting the broken form.
7. The installed isolation mechanism can prevent recursive model invocation from the agent
   namespace while still permitting the controller-owned Claude session and approved non-model
   tools. Activation must prove that `claude`, `codex`, worker entrypoints, absolute and symlinked
   aliases, copied entrypoints, and runtime-mediated equivalents cannot execute after session
   startup. Failure blocks activation.
8. Repository line-level inspection could not be performed during drafting because every local
   command failed before execution with the documented bwrap `RTM_NEWADDR` error, and the drafting
   session’s filesystem was read-only. Claude’s next review must reconcile these citations against
   the tree and replace stale paths or add line numbers before authorization.

## 3. Requirements & acceptance criteria (numbered, testable)

1. Without a valid local activation grant, or with HALT present, starting either outer-loop unit
   SHALL launch no Claude process or detached job and SHALL persist `DISABLED` or `HALTED`.
2. Every activation grant SHALL name a grant UUID, issuance/not-before time, UTC expiry,
   `iteration_limit`, `detached_job_launch_limit`, `model_invocation_limit`,
   `same_plan_revision_streak_limit`, a finite `iteration_wall_clock_ceiling` defaulting to four
   hours, `exact_session_resume_limit_per_iteration`, `autonomy_mode`, authorized PLAN-006 digest,
   scope, and allowed broker capabilities.
3. Budget consumption SHALL require no provider API. The controller SHALL atomically reserve one
   iteration unit before opening each iteration, one detached-job unit before admitting each new
   job launch, and one model-invocation unit before every model-bearing prompt, process launch,
   exact-session resume, worker dispatch, or detached model job.
4. Budget counters SHALL be durable, keyed to the grant UUID, monotonic, idempotent by
   iteration/job/invocation UUID, and preserved across controller restart, user-manager restart, and
   reboot.
5. The controller SHALL emit a pre-exhaustion warning for each positive budget and SHALL admit no
   action beyond its ceiling. Reaching a ceiling SHALL latch `STOPPED_BUDGET`, write
   `ATTENTION.json`, and prevent further iterations, job launches, model invocations, or broker
   operations that would initiate a model until a new valid operator grant is installed.
6. A configurable value floor SHALL stop the loop after N validated revisions of the same plan ID
   since the last independently validated, externally meaningful transition linked to that plan or
   request. The recommended and default N SHALL be 3. Companion `VERDICT`,
   `DECISION_RECORD`, failure, recovery, other-plan, or loop-internal artifacts SHALL neither mask a
   revision nor reset the count. Only a merged PR, terminal attempt gate outcome, request-ledger row
   reaching `done` or `blocked`, or independently receipted operator-visible deliverable SHALL reset
   the applicable count.
7. A submitted operator event or detached-job completion SHALL be durably spooled before
   acknowledgement and delivered to an idle healthy agent within five seconds on the test clock,
   without waiting for a heartbeat.
8. A detached job SHALL remain owned by an independent systemd unit after a Claude turn or process
   exits. Its request, budget reservations, unit identity, status, output digest, terminal manifest,
   completion event, liveness samples, and stall counter SHALL survive controller downtime and be
   reconciled exactly once.
9. The job wrapper SHALL persist and fsync the terminal manifest and completion event before
   attempting socket notification.
10. On a recognized usage-limit message, the controller SHALL transition the open iteration to
    `WAITING_USAGE_RESET`, persist the exact Claude session ID and reset deadline, make no model
    probes while waiting, and automatically resume that same session after reset if the iteration
    wall-clock ceiling has not expired. If it has expired, the old iteration SHALL already be
    finalized and reset delivery SHALL require a newly reserved iteration and model invocation.
    Usage waiting SHALL not increment crash or failure counters.
11. An unmatched usage/liveness condition SHALL not enter `WAITING_USAGE_RESET`. It SHALL create a
    classifier-mismatch alert containing raw unparsed pane evidence and follow the bounded
    classifier-independent probe protocol in §4.5.
12. No liveness probe SHALL occur while a registered `WAITING_JOB` or recognized
    `WAITING_USAGE_RESET` condition remains valid. Detached-job liveness SHALL instead be governed by
    the independent job protocol in §4.6.
13. A liveness probe SHALL resume the same explicit session UUID, SHALL open a separately identified
    `LIVENESS_PROBE` iteration, and SHALL consume one ordinary iteration-budget unit and one
    model-invocation unit.
14. Probe resumes SHALL occur no more than once per thirty minutes, only after two consecutive
    ten-minute no-progress samples or an unexplained agent exit, and at most three times per anomaly.
    Budget exhaustion, HALT, grant expiry, a second confirmed wedge, or successful classification
    SHALL terminate the probe schedule earlier.
15. Exhausting the probe allowance without a valid Stop disposition or recognized state SHALL enter
    `STOPPED_UNCLASSIFIED`, retain raw evidence, and alert. It SHALL never become an indefinite idle
    state.
16. A controller restart, user-manager restart, or host reboot SHALL reconstruct state, reconcile
    units/events/budgets, and resume the same open iteration and Claude session, or enter an explicit
    fail-closed stop state. Conversation memory alone SHALL never be required.
17. Every automated turn SHALL belong to exactly one controller-created open iteration. Waiting for a
    registered job or recognized usage reset pauses that iteration instead of closing it unless its
    absolute wall-clock ceiling expires, in which case the iteration is finalized mechanically and
    the independent job/reset condition remains durable for a later newly admitted iteration.
18. Every recovery probe is a new iteration because its predecessor ended or was force-terminated
    without a valid Stop disposition. The predecessor SHALL be finalized with mechanical evidence;
    it SHALL not be silently reused to evade the iteration or model-invocation budget.
19. An iteration SHALL be `SUCCESS` only when the independent validator finds at least one
    allowlisted, schema-valid semantic artifact delta against its start baseline and records
    before/after digests or immutable remote identity.
20. Loop state, logs, heartbeats, job manifests, timestamps, PENDING/NEXT prose, alerts,
    `ATTENTION.json`, the iteration’s own ledger entry, controller-recovery records, and job-liveness
    samples SHALL never count as progress or reset the value floor.
21. A turn that stops without a valid delta and without entering legitimate `WAITING_JOB` or
    `WAITING_USAGE_RESET` SHALL close `FAILED/NO_DURABLE_DELTA`, write evidence and an
    operator-visible alert, and enter `DIAGNOSING`.
22. Every finalized iteration SHALL record its trigger, kind, selected work, intent/hypothesis,
    actions, outcome, validated artifacts, failure class/fingerprint, all budget counters,
    wall-clock deadline, exact-session resume count, and typed next step. Entries SHALL form a
    SHA-256 chain; tampering or truncation SHALL stop the loop before another model invocation.
23. `WORK_EXHAUSTED`, `OPERATOR_BLOCKED`, budget exhaustion, value-floor exhaustion,
    `VALIDATOR_COMPROMISED`, `LEDGER_CORRUPT`, two consecutive identical ordinary failure
    fingerprints, three agent crashes in sixty minutes, two confirmed wedges of one iteration,
    `STOPPED_JOB_WEDGE`, failed controller recovery, or iteration wall-clock expiry SHALL stop the
    affected agent/admission path and produce durable operator-visible evidence.
24. A busy agent SHALL be declared wedged only after two consecutive ten-minute samples show all of:
    an active nonwaiting turn, no pane/log change, no CPU-time increase, no job progress, and no
    hook/event activity. A busy-but-silent process with advancing CPU SHALL survive.
25. Creating HALT SHALL prevent new side effects, stop the agent cgroup and all outer-loop-owned job
    units, and persist `HALTED`. Every broker action SHALL recheck HALT immediately before execution.
    Removing HALT alone SHALL not resume work.
26. The persistent Claude unit SHALL have no GitHub token, SSH key/agent, Codex credential, sudo,
    user-systemd bus, writable installed controller/validator/ledger, or executable model
    entrypoints other than the controller-owned initial session image. Negative tests SHALL prove
    these resources and recursive model paths inaccessible.
27. GitHub/systemd actions requested by the agent SHALL pass through an allowlisted broker using the
    installed parent dispatcher. The broker SHALL reject remote main, reject autonomous merge of
    trust-critical work, reject actions forbidden by the grant’s `autonomy_mode`, and reject
    absent/invalid high-risk approval.
28. `codex-consult` SHALL use complete digest-bound stdin/inlined context in an externally hardened
    detached unit. Its wrapper SHALL refuse repository-reading sandbox invocation until the host
    bwrap/AppArmor defect is fixed, evidenced, reviewed, and separately authorized.
29. Controller, heartbeat, reset scheduler, job watcher, and health classifier SHALL make zero
    Claude/Codex/API calls. Only a controller-authorized ordinary turn, detached model job, worker
    dispatch, or bounded liveness-probe iteration with a committed model-invocation reservation may
    invoke a model.
30. The heartbeat SHALL detect and recover a dead or stale controller lease, missed event, overdue
    reset deadline, classifier mismatch, or confirmed wedge, but SHALL not prompt an idle agent
    merely to ask for status. Controller recovery SHALL not require the controller’s flock.
31. The five regression scenarios—usage exhaustion, detached completion while idle, reboot, wedge,
    and no-delta iteration—SHALL fail against the preserved old-design fixture and pass against the
    new controller.
32. Dedicated regression scenarios for classifier drift, all three budget meters, value-floor
    stopping, autonomy modes, recursive-model refusal, controller recovery, detached-job liveness,
    iteration wall-clock expiry, exact-session resume idempotency, and refusal of the broken Codex
    invocation SHALL pass.
33. Real installed-CLI hook/session/parser smoke tests and an operator-approved actual reboot drill
    SHALL pass before R23 is marked done.
34. For every nonterminal detached job, the watcher SHALL sample unit state, cumulative CPU time,
    raw JSONL/stream size, response/output size, and declared progress-file mtimes at a conservative
    job-kind interval defaulting to fifteen minutes. Any advancing signal SHALL reset the
    consecutive-stall counter. All signals flat across two consecutive samples SHALL emit
    `JOB_OVERDUE`, update `ATTENTION.json`, and journal an alert. Four consecutive stalled windows
    by default SHALL capture evidence, terminate and verify the unit inactive, emit
    `JOB_WEDGE_CONFIRMED`, and enter `STOPPED_JOB_WEDGE`.
35. Detached-job stall thresholds SHALL be finite, installed-policy values with job-kind overrides,
    recorded in the request before launch. They SHALL not be changed by the agent. The
    `codex-consult` policy SHALL have no elapsed-time liveness timeout: a job with advancing CPU,
    stream, output, or progress metadata SHALL survive regardless of age.
36. The independent heartbeat SHALL persist alerts through its own atomic spool and lock, kill a
    stale controller cgroup, start or restart the controller, and verify that the controller lease
    sequence advances within a bounded verification interval. After three failed recovery attempts
    in sixty minutes by default, it SHALL create a durable `CONTROLLER_RECOVERY_STOP` sentinel,
    stop the controller, agent, and registered jobs, persist a standalone `ATTENTION.json`, and warn
    at emergency journal severity.
37. Every worker dispatch SHALL be represented as a named detached job and SHALL atomically reserve
    both one detached-job unit and one model-invocation unit before the installed dispatcher may
    create a worker process. `BROKER_OPERATION` SHALL be structurally incapable of launching a model
    without such reservations.
38. Every admitted iteration SHALL have a persisted absolute wall-clock deadline, defaulting to
    `started_at + PT4H`. At the deadline the controller SHALL capture evidence, terminate the Claude
    cgroup, finalize the iteration as `FAILED/ITERATION_WALL_CLOCK_EXCEEDED`, and prevent replay of
    its prompt. Independently progressing detached jobs SHALL remain subject to §3.34–3.35, not the
    iteration deadline.
39. Every actual exact-session start or resume SHALL have a distinct model-invocation reservation.
    Reconciliation with the same invocation UUID SHALL be idempotent but SHALL never cause a second
    prompt or process launch. The default per-iteration exact-session resume limit SHALL be three;
    reaching it SHALL stop further resumes with durable evidence even if grant-wide model budget
    remains.
40. A plan’s value-floor count SHALL persist across failed iterations, no-delta iterations,
    liveness probes, classifier recovery, companion verdicts/decisions, revisions of other plan IDs,
    and new activations using the same grant. Only a validated externally meaningful transition
    causally linked to the plan/request SHALL reset it.

## 4. Design / approach

### 4.1 Activation and bootstrap boundary

The active loop is an installed, digest-bound control-plane snapshot, not code imported from the
mutable repository checkout. The repository contains source, schemas, tests, unit templates, and
fixtures. After authorization, an operator-only installer copies the authorized controller,
validator, schemas, prompt, and units into a versioned installation directory and records the
PLAN-006 revision digest.

The Claude service sees this installation read-only. Candidate changes therefore cannot validate,
install, or activate themselves.

Tracked policy ships disabled. A gitignored local activation grant contains at least:

```json
{
  "schema_version": 1,
  "grant_id": "UUID",
  "authorized_plan": {
    "id": "PLAN-006",
    "revision": 3,
    "sha256": "hex"
  },
  "operator_identity": "local operator identity",
  "issued_at": "RFC3339 UTC",
  "not_before": "RFC3339 UTC",
  "expires_at": "RFC3339 UTC",
  "scope": {
    "request_ids": ["R23"],
    "plan_ids": ["PLAN-006"],
    "spec_ids": []
  },
  "autonomy_mode": "full_except_high_risk_dispatch",
  "allowed_broker_capabilities": [
    "plan",
    "review",
    "research",
    "worker_dispatch_low_risk",
    "open_pr_to_integration"
  ],
  "iteration_limit": 12,
  "detached_job_launch_limit": 6,
  "model_invocation_limit": 18,
  "same_plan_revision_streak_limit": 3,
  "iteration_wall_clock_ceiling": "PT4H",
  "exact_session_resume_limit_per_iteration": 3,
  "provider_window_fallback_upper_bound": "PT5H"
}
```

`autonomy_mode` is mandatory and has two initial values:

1. `full_except_high_risk_dispatch` — recommended. The loop may use all lanes and broker
   capabilities explicitly present in the grant except high-risk dispatch. High-risk dispatch still
   requires a per-dispatch approval artifact that the loop cannot mint, and this autonomy mode does
   not allow the loop to execute it autonomously even if it drafts or requests that approval.
2. `night_plans_reviews_research` — conservative. The loop may create plans, conduct reviews, and
   launch bounded research/consultation jobs. It may not dispatch workers, open or merge PRs,
   integrate attempts, or make system/remote changes.

The effective authority is the intersection of `autonomy_mode`, grant scope, named broker
capabilities, repository policy, and existing approval artifacts. A wider capability list cannot
override a narrower mode.

The grant window is `[not_before, expires_at)`. Counters never reset because a provider window might
have reset; only a new operator-issued grant UUID creates new counters. Replacing a grant does not
erase the previous grant’s audit record.

The controller refuses missing, expired, widened, malformed, or digest-mismatched grants.
`WAITING_JOB` and `WAITING_USAGE_RESET` do not consume additional iteration units or launch units.
They consume a model-invocation unit only when an actual exact-session start/resume occurs. A
liveness probe consumes both an iteration unit and a model-invocation unit because it invokes the
model.

The provider-window fallback is a scheduling bound for an already-observed but time-unparseable
usage condition. It is not a spend budget and cannot override any grant ceiling.

The wall-clock ceiling is finite activation data. `PT4H` is the default. A missing, zero, negative,
or unbounded value blocks activation. Its deadline is persisted when the iteration opens and cannot
be extended by the agent, a companion artifact, a wait transition, a controller restart, or a
session resume. An operator-authorized policy may choose another generous finite duration, but no
job-kind policy may turn it into an unbounded Claude iteration.

The exact-session resume limit is independent of the grant-wide model-invocation limit. Both must
permit a resume. The installed default is three actual resumes per iteration. Reusing a reservation
UUID for reconciliation never grants permission to deliver a second prompt.

### 4.2 Runtime components

1. `orchestrator-outer-loop.service` runs the deterministic controller in the foreground with
   `Restart=always`, a bounded `RestartSec`, and an installed start-limit policy. It owns state,
   events, deadlines, jobs, ledger, validation, budgets, health, alerts, and capability decisions.
   It performs no model calls directly.
2. `orchestrator-outer-agent.service` runs a small installed runner that creates an isolated tmux
   server on a dedicated socket, starts interactive Claude with a controller-assigned UUID and
   committed model-invocation receipt, enables pipe-pane logging, and remains tied to that tmux
   lifecycle. It has `Restart=no`: the controller must classify the exit before any relaunch.
3. `orchestrator-outer-heartbeat.timer` performs zero-quota local inspection every ten minutes. It
   covers missed spool notifications, controller-lease recovery, health sampling, deadlines, budget
   expiry, and anomaly escalation. It is not the ordinary driver.
4. `orchestrator-outer-heartbeat.service` is independent of the controller process, controller
   socket, and controller-wide flock. It writes a separate atomic recovery spool and lease-recovery
   journal, may stop/start the named controller cgroup through the user manager, verifies a
   post-restart lease advance, and owns the durable controller-recovery stop sentinel.
5. `scripts/outer-loop` is the client/operator interface: enable, disable, submit, status, attach,
   resume, halt, event, job submit/status, iteration inspect, grant inspect, budget inspect, and
   install.
6. The Claude Stop hook submits hook JSON to the installed client. It never writes state, budget, or
   ledger directly.
7. Detached work runs as `orchestrator-outer-job@<job-id>.service` or equivalent transient units
   created from validated named descriptors. The wrapper writes an atomic terminal manifest and
   completion event before attempting notification.
8. `orchestrator-outer-job-watch.service` or the deterministic watcher path samples each
   nonterminal job’s unit state, cumulative CPU time, stream/output byte counts, digests where
   bounded, and declared progress-file mtimes. Its observations are quota-free and durable.
9. Runtime state lives beneath `.orchestrator/outer-loop/`: `state.json`, event
   inbox/processed, registered jobs, open iterations, grant counters, ledger entries, `chain.head`,
   logs, raw pane evidence, health, alerts, `ATTENTION.json`, and Claude session identity. Runtime
   content is gitignored except intentional schemas and hash checkpoints.
10. Heartbeat recovery evidence lives in a separate controller-independent runtime namespace with
    its own lock: recovery attempts, standalone alerts, lease observations,
    `CONTROLLER_RECOVERY_STOP`, and its standalone `ATTENTION.json`. The controller imports those
    records idempotently when healthy but does not own their durability.

All JSON is canonical UTF-8 with sorted keys and no floats. Writes use same-filesystem temporary
files, fsync, atomic rename, and directory fsync. A controller-wide flock serializes controller
mutation. The heartbeat never acquires or waits on that flock. Events, iterations, jobs,
reservations, invocations, alerts, and recovery attempts are idempotent by UUID.

The controller lease contains a boot ID, controller instance UUID, monotonic sequence, UTC
observation time, and monotonic timestamp. The controller advances and fsyncs it on a short local
cadence independent of model activity. A lease from another boot, an over-age timestamp, or a
nonadvancing sequence across heartbeat observations is stale.

### 4.3 State machine

| State | Meaning | Machine-checked transitions |
|---|---|---|
| `DISABLED` | No valid activation grant | valid ENABLE → `STARTING`; HALT_SET → `HALTED` |
| `STARTING` | Verify ledger/policy/grant; reconcile jobs, budgets, events, session | eligible work and budgets → `ITERATING`; none → `STOPPED_WORK_EXHAUSTED`; integrity error → `STOPPED_INTEGRITY` |
| `READY` | Agent alive at Stop-hook-confirmed prompt | eligible OPERATOR_INPUT, JOB_COMPLETED, NEXT_STEP_READY plus budgets → `ITERATING` |
| `ITERATING` | One automated turn and one open iteration active | JOB_REGISTERED → `WAITING_JOB`; recognized usage → `WAITING_USAGE_RESET`; valid STOP_HOOK → `READY`/stopped state; no-delta STOP_HOOK → `DIAGNOSING`; unexplained AGENT_EXIT → `RECOVERING_UNCLASSIFIED`; wall deadline → `ITERATION_EXPIRED` |
| `WAITING_JOB` | Open iteration paused on registered work | matching JOB_COMPLETED/JOB_INTERRUPTED → `ITERATING`; recognized usage → `WAITING_USAGE_RESET`; wall deadline → `ITERATION_EXPIRED_JOB_PENDING`; job wedge → `STOPPED_JOB_WEDGE` |
| `WAITING_USAGE_RESET` | Open iteration paused to persisted reset deadline | RESET_DEADLINE_REACHED before iteration deadline → `ITERATING` in the same explicit session; iteration deadline first → `ITERATION_EXPIRED_RESET_PENDING` |
| `ITERATION_EXPIRED_JOB_PENDING` | Iteration finalized at its wall deadline; independent job remains registered | matching terminal job event plus fresh budgets → new `ITERATING`; job wedge → `STOPPED_JOB_WEDGE`; budget/grant stop → stopped state |
| `ITERATION_EXPIRED_RESET_PENDING` | Iteration finalized at its wall deadline; recognized reset deadline remains durable | RESET_DEADLINE_REACHED plus fresh budgets → new `ITERATING` in the same explicit session; budget/grant stop → stopped state |
| `RECOVERING_UNCLASSIFIED` | No valid Stop/wait classification; raw evidence retained; bounded probe schedule active | recognized usage → `WAITING_USAGE_RESET`; valid Stop → normal validation; probe due and budgets → new `LIVENESS_PROBE` iteration; probe/budget/wedge limit → stopped state |
| `DIAGNOSING` | Failed iteration and alert recorded | one DIAGNOSE event plus budgets → `ITERATING`; identical ordinary repeat → `STOPPED_REPEATED_FAILURE` |
| `RECOVERING` | Classified crash/wedge evidence captured | recoverable and within budgets/resume bound → `STARTING`; repeated failure → stopped state |
| `STOPPED_WORK_EXHAUSTED` | No eligible work | new scoped operator input/grant → `STARTING` |
| `STOPPED_OPERATOR_BLOCKED` | Named human decision/approval required | matching operator/approval event → `STARTING` |
| `STOPPED_BUDGET` | A grant counter is exhausted or grant expired | new operator grant → `STARTING` |
| `STOPPED_VALUE_FLOOR` | Per-plan unshipped revision count reached N | explicit disposition-bearing RESUME with new/revised grant → `STARTING` |
| `STOPPED_JOB_WEDGE` | Registered detached job remained flat through its bounded stalled windows | explicit evidence-bearing operator disposition and RESUME only |
| `STOPPED_CONTROLLER_RECOVERY` | Independent heartbeat exhausted bounded controller recovery | explicit repair, sentinel clearance, and RESUME only |
| `STOPPED_ITERATION_CEILING` | An admitted iteration reached its finite wall-clock ceiling without a durable deferred condition | explicit disposition-bearing RESUME only |
| `STOPPED_INVOCATION_BOUND` | Exact-session resume bound reached | explicit disposition-bearing RESUME or new grant only |
| `STOPPED_REPEATED_FAILURE` | Ordinary repeated-failure breaker open | explicit disposition-bearing RESUME only |
| `STOPPED_INTEGRITY` / `STOPPED_UNCLASSIFIED` | State, protocol, or validation untrustworthy | explicit repair and RESUME only |
| `HALTED` | HALT active; agent/jobs stopped | HALT absent plus explicit RESUME and valid grant → `STARTING` |

`READY`, `WAITING_JOB`, and `WAITING_USAGE_RESET` are idle-but-healthy. `READY` is not inferred from a
prompt glyph; it requires a matching Stop hook. Waiting states require a registered live job or
recognized usage evidence.

`WAITING_USAGE_RESET` has no quota polling loop. Local deadline/health inspection continues, but no
Claude/Codex process is started before its deadline merely to ask whether quota returned.

A registered job is not healthy merely because its unit remains active. Its independent liveness
state is healthy only while it has not crossed the installed all-signals-flat thresholds in §4.6.

`RECOVERING_UNCLASSIFIED` is not a waiting state. It is a bounded recovery state with a next-probe
deadline, remaining probe allowance, iteration/model-budget dependency, raw evidence, and mandatory
operator alert.

The iteration deadline is absolute. If it expires during a valid job or usage wait, the controller
finalizes the iteration but retains the independently verifiable deferred condition. Completion or
reset may later open a new iteration only after fresh iteration and model-invocation reservations.

Work selection and conclusions remain model judgments. Event identity, transitions, budgets, unit
liveness, digests, validation, alerts, and stops are machine-checked.

### 4.4 Event model

Primary event types are `JOB_COMPLETED`, `USAGE_RESET`, and `OPERATOR_INPUT`. Internal events include
`SERVICE_START`, `JOB_INTERRUPTED`, `JOB_OVERDUE`, `JOB_PROGRESS_RESUMED`,
`JOB_WEDGE_CONFIRMED`, `NEXT_STEP_READY`, `STOP_HOOK`, `AGENT_EXIT`, `HEALTH_SAMPLE`,
`RESET_DEADLINE_REACHED`, `ITERATION_WALL_CLOCK_EXCEEDED`, `CLASSIFIER_MISMATCH`,
`LIVENESS_PROBE_DUE`, `BUDGET_WARNING`, `BUDGET_EXHAUSTED`, `MODEL_INVOCATION_RESERVED`,
`SESSION_RESUME_BOUND_REACHED`, `VALUE_FLOOR_REACHED`, `CONTROLLER_LEASE_STALE`,
`CONTROLLER_RECOVERY_ATTEMPT`, `CONTROLLER_RECOVERED`, `CONTROLLER_RECOVERY_FAILED`,
`CONTROLLER_RECOVERY_STOP`, `HALT_SET`, and `DIAGNOSE`.

Each event records schema version, UUID, type, UTC creation time, source, correlation/iteration/job/
invocation identity, payload path and SHA-256, required scope, and its own digest. Job output and pane
text are explicitly marked untrusted data.

An event file is atomically persisted and fsynced before the client acknowledges it or nudges the
controller socket. Socket loss therefore cannot lose the event. Processed state advances only once a
finalized/open iteration references that event.

When `READY`, the controller:

1. verifies grant, mode, scope, HALT, expiry, iteration budget, model-invocation budget, and
   per-iteration bounds;
2. atomically reserves one iteration unit and one model-invocation unit for new UUIDs in one durable
   admission transaction;
3. creates the open iteration with an absolute wall-clock deadline;
4. captures the progress-artifact baseline;
5. loads a fixed digest-bound envelope into the isolated tmux buffer;
6. pastes it into the idle Claude PTY and sends Enter exactly once under the invocation receipt.

It never interpolates event text into a shell command. Events arriving during `ITERATING` remain
queued. A completion matching `WAITING_JOB` is delivered immediately into the same open iteration
only if its wall-clock deadline remains unexpired. Events arriving during a recognized usage wait
remain durable until reset.

A delivery attempt records a pre-delivery marker and a post-delivery observation. If the controller
crashes between them, reconciliation treats the model-invocation reservation as consumed. It
inspects the session, pane, hook sequence, and unit identity; it either observes that delivery
occurred or stops for explicit recovery. It never sends the same envelope again under the same
invocation UUID.

Operator input normally uses `scripts/outer-loop submit`. Read-only observation uses the dedicated
tmux socket with `attach -r`. Writable emergency attachment is an audited override, not routine
input.

### 4.5 Runtime, usage classification, and classifier-independent liveness

The manager is persistent interactive Claude, never `claude -p`. First activation assigns an
explicit session UUID. Every later launch names or resumes exactly that UUID. “Resume most recent”
is prohibited.

Every first prompt, process relaunch, and exact-session resume requires a committed
`MODEL_INVOCATION` reservation. Reconciliation may inspect an existing process under an existing
reservation, but an action that could cause another provider invocation requires a fresh invocation
UUID. Each open iteration records its actual resume count. The installed default permits three
exact-session resumes per iteration; reaching either that bound or the grant-wide model-invocation
ceiling prevents the resume and enters the corresponding stopped state.

tmux provides the PTY and observation surface. systemd provides boot start, cgroup ownership, exit
status, logs, resource limits, and filesystem/credential boundaries. The dedicated tmux socket
prevents stopping the outer-loop service from affecting unrelated operator tmux sessions.

The primary health classifier distinguishes conditions without spending quota:

- **Recognized usage exhaustion:** a version-pinned, ANSI-stripped parser recognizes a complete
  known exhaustion record and, when present, a reset instant. It records
  `WAITING_USAGE_RESET` before acting.
- **Classified crash:** the Claude/tmux lifecycle ends with evidence inconsistent with a planned
  stop, recognized usage exhaustion, or registered waiting condition.
- **Idle healthy:** the PID/session exists and the last matching Stop hook closed the turn, or a
  registered waiting condition exists.
- **Busy healthy:** an open iteration has advancing pane bytes, CPU time, hook/events, or job
  progress.
- **Wedged:** all progress signals remain unchanged for two consecutive ten-minute samples while
  the turn is active and not waiting.
- **Controller dead or stale:** the independent heartbeat observes a missing or nonadvancing lease
  and executes the recovery protocol below.

Usage classification must resist output spoofing: known CLI framing, state correlation, and
negative fixtures containing fake limit text in tool/job output are required.

The classifier is not authoritative for liveness. The following independent fallback applies when:

1. the agent process exits without a valid Stop disposition, registered wait, or recognized usage
   record; or
2. an active nonwaiting turn reaches the two-sample wedge threshold and must be terminated; or
3. the controller observes an ended turn with no valid Stop disposition and no progress signal
   capable of advancing it.

At anomaly time `T0`, before normalization or relaunch, the controller SHALL:

1. copy the raw pipe-pane bytes for the affected turn, including ANSI/control bytes, into an
   immutable evidence file;
2. record the raw file’s path, byte count, SHA-256, capture boundaries, agent exit/unit metadata,
   current session UUID, iteration UUID, invocation UUID, installed CLI version, and classifier
   result;
3. emit `CLASSIFIER_MISMATCH`;
4. create or update `.orchestrator/outer-loop/ATTENTION.json` with severity `warning`,
   `classifier_match: false`, the evidence references/digests, next probe time, remaining probe
   allowance, and all budget remaining;
5. warn in the systemd journal;
6. enter `RECOVERING_UNCLASSIFIED`, not `WAITING_USAGE_RESET`.

The raw pane evidence is retained unparsed. A separately derived sanitized/ANSI-stripped view may be
used for diagnostics, but it never replaces the raw evidence and its digest.

#### Probe-resume schedule

The schedule is deterministic:

1. Local health samples remain ten minutes apart.
2. A live silent process is not disturbed after the first stalled sample. The second consecutive
   stalled sample confirms a wedge.
3. For an unexplained exit, `T0` is the recorded lifecycle end. For a confirmed live wedge, `T0` is
   the second stalled sample, after evidence capture and the permitted cgroup recovery action.
4. The first probe is eligible at `T0 + 30 minutes`.
5. Later probes are eligible no sooner than thirty minutes after the preceding probe.
6. At most three probes may be opened for one anomaly chain.
7. Immediately before each probe, the controller rechecks HALT, grant identity/expiry,
   `autonomy_mode`, iteration budget, model-invocation budget, queued events, live jobs, recognized
   usage state, Stop-hook state, session identity, and per-iteration resume bound.
8. A valid queued completion or registered wait cancels the probe and follows the normal event
   transition.
9. A recognized usage record cancels the probe schedule and enters `WAITING_USAGE_RESET`.
10. A valid Stop disposition cancels the schedule and follows normal validation.
11. If no iteration unit or model-invocation unit remains, the controller enters
    `STOPPED_BUDGET`; it does not probe.
12. A probe opens a new iteration with `iteration_kind: LIVENESS_PROBE`, atomically consumes one
    ordinary iteration unit and one model-invocation unit, creates a four-hour-default absolute
    deadline, and resumes the same explicit Claude session UUID with a fixed, minimal,
    digest-bound recovery envelope.
13. The envelope identifies the anomaly/event but does not trust or interpret the pane text. It asks
    the resumed session to process queued durable events and terminate through the normal Stop hook.
14. If the probe again produces unmatched output or ends without a valid disposition, raw evidence
    is appended to the anomaly chain and the next thirty-minute deadline is scheduled.
15. After three unsuccessful probes, after the second confirmed wedge of the same recovery chain, or
    when the exact-session resume bound is reached, the controller enters
    `STOPPED_UNCLASSIFIED` or `STOPPED_INVOCATION_BOUND` as applicable, upgrades
    `ATTENTION.json` to severity `stop`, stops the agent, and waits for explicit operator
    disposition.

The prior anomalous iteration is finalized before a probe iteration opens. It records
`FAILED/UNCLASSIFIED_TURN_END` or `FAILED/WEDGE_RECOVERY`, raw evidence, and the fact that the
special bounded classifier-recovery policy applies. These recovery failures are counted by the
three-probe anomaly breaker; they are not allowed to cause infinite immediate retries, and they do
not bypass either the iteration or model-invocation meter.

This schedule is intentionally conservative: upstream CLI drift may cause up to three extra,
budgeted resumes, but it cannot produce indefinite silence or unbounded spend.

For recognized usage, the reset deadline comes from an already-observed message under `TZ=UTC` and
`LC_ALL=C`. Reboot reconstructs it from the persisted UTC instant. If exhaustion is recognized but
no reset time is available, the grant’s conservative provider-window upper bound supplies one
deadline and permits one exact-session resume attempt. A repeated recognized-but-time-unparseable
exhaustion enters `STOPPED_UNCLASSIFIED`. There is no periodic quota probe.

At an open iteration’s wall-clock deadline, the controller captures pane, hook, cgroup, session, and
deferred-condition evidence; terminates and verifies the Claude cgroup inactive; and finalizes the
iteration as `FAILED/ITERATION_WALL_CLOCK_EXCEEDED`. It never replays that iteration’s prompt. A
registered progressing detached job is not killed by this deadline: its request and eventual
completion remain independently durable. Likewise, a recognized reset deadline remains durable,
but its eventual resumption opens a new iteration and reserves a new model invocation.

#### Independent controller recovery

The heartbeat uses the controller lease, systemd unit state, and heartbeat’s own prior observations.
It does not call the controller, acquire the controller flock, or rely on controller-owned alert
mutation.

On a missing or stale lease it SHALL:

1. atomically append `CONTROLLER_LEASE_STALE` to the heartbeat recovery spool and update its
   standalone `ATTENTION.json`;
2. record the observed lease, boot ID, unit state, cgroup identity, and recovery-attempt UUID;
3. issue a user-manager kill for the entire stale controller cgroup and verify that the old cgroup
   has no remaining processes;
4. issue an explicit start or restart of `orchestrator-outer-loop.service`;
5. wait only for the installed bounded verification interval and verify a new controller instance or
   restarted instance advances the lease sequence with a fresh monotonic timestamp;
6. record `CONTROLLER_RECOVERED` on success and leave the controller to reconcile the independent
   recovery records;
7. record `CONTROLLER_RECOVERY_FAILED` on failure.

The default breaker is three failed recovery attempts within sixty minutes. On reaching it, the
heartbeat atomically creates `CONTROLLER_RECOVERY_STOP`, updates its standalone
`ATTENTION.json` to severity `stop`, stops the controller, agent, and all registered outer-loop job
units directly through the user manager, verifies their cgroups inactive, and journals at emergency
severity. The sentinel is checked before every controller startup and prevents model or broker
admission until an operator repairs the cause, explicitly clears the sentinel through the installed
operator command, and supplies a disposition-bearing resume.

### 4.6 Detached jobs

The agent requests named job kinds through the controller; arbitrary argv is rejected. The
controller validates the request and autonomy mode, assigns a job UUID, records the request, and
rechecks HALT, grant expiry, scope, detached-job budget, and—when model-bearing—the
model-invocation budget.

Immediately before requesting the independent systemd unit, the controller atomically reserves one
detached-job-launch unit keyed by the job UUID. A model-bearing job also reserves one
model-invocation unit keyed by a distinct invocation UUID in the same durable admission transaction.
A failed `systemd` launch remains consumed because the launch was admitted and could have produced
an incompletely observed process. Reconciliation by job/invocation UUID prevents double decrement
or double launch.

Every worker dispatch is a named detached model job. The broker may validate and prepare it, but
`BROKER_OPERATION` cannot directly call the dispatcher’s model-launch path. Before the installed
dispatcher creates a worker process, it verifies a controller-issued receipt binding the grant,
job UUID, invocation UUID, worker descriptor digest, scope, and unit identity. Each new worker
attempt or remediation model process requires new detached-job and model-invocation reservations.

The job is not a descendant of the Claude process and survives the end of a turn.

The job wrapper atomically records:

- job ID, kind, and descriptor digest;
- grant ID and all budget-reservation receipts;
- model-invocation ID when applicable;
- unit identity;
- start/end timestamps;
- liveness policy identity and thresholds;
- exit classification/status;
- response/output, stderr, raw-stream paths, and digests;
- completion-event ID.

It persists and fsyncs the terminal manifest and completion event before attempting socket
notification. On startup, the controller reconciles every nonterminal job against actual unit state.
A unit lost to reboot becomes `JOB_INTERRUPTED`, never silent success or eternal waiting.

#### Detached-job liveness protocol

Every job kind has an installed, immutable liveness descriptor. The default sample interval is
fifteen minutes, `overdue_after_consecutive_flat_samples` is two, and
`stop_after_consecutive_flat_windows` is four. A separately authorized job-kind policy may choose
more conservative finite thresholds. The agent cannot weaken or extend them.

For each nonterminal job, a sample records:

1. unit active/substate, invocation ID, main PID, and cgroup membership;
2. cumulative cgroup CPU time;
3. raw JSONL/event-stream byte count and last durable record offset;
4. stdout, stderr, response, and declared output byte counts;
5. mtimes and optional monotonic counters of declared progress files;
6. job-wrapper heartbeat or hook sequence when the kind supplies one;
7. the preceding sample digest and current consecutive-flat count.

The comparison is conservative:

- any increase in CPU time, stream offset, output size, declared progress counter, or relevant mtime
  resets the consecutive-flat count to zero and clears an outstanding warning with
  `JOB_PROGRESS_RESUMED`;
- a unit-state transition is recorded and reconciled rather than treated as flat;
- only when the unit remains nonterminal and every progress signal is unchanged does one flat window
  accrue;
- a signal that cannot be read is an observation failure, not proof of progress. Repeated
  observation failure fails closed with evidence rather than granting eternal health.

After two consecutive all-flat samples, the watcher emits `JOB_OVERDUE`, writes or updates
`ATTENTION.json` with severity `warning`, records all sample digests and unit metadata, and journals
the warning. `WAITING_JOB` remains registered but is no longer silently healthy.

At four consecutive flat windows by default, the watcher:

1. captures final unit/cgroup status, cumulative CPU, raw streams, output digests, progress metadata,
   and the complete linked sample chain;
2. emits `JOB_WEDGE_CONFIRMED`;
3. sends the installed graceful termination signal, waits the bounded termination grace, then kills
   the entire job cgroup if necessary;
4. verifies the unit and cgroup inactive;
5. writes a terminal `JOB_INTERRUPTED` manifest with failure class `JOB_WEDGE`;
6. persists the terminal event before notification;
7. updates `ATTENTION.json` to severity `stop`; and
8. enters `STOPPED_JOB_WEDGE`.

This is a progress-stall protocol, not an elapsed-runtime timeout. A `codex-consult` that runs for
hours or days while any CPU, JSON stream, output, or declared progress signal advances never accrues
a flat window and is not terminated by this protocol.

#### Hard precondition for `codex-consult`

Job kind `codex-consult` MUST:

1. receive complete, bounded, secret-stripped, digest-bound context through stdin or an equivalent
   inlined-context channel prepared outside the model job;
2. use the proven non-repository-reading invocation;
3. run in its external hardened systemd boundary;
4. use `gpt-5.6-sol`, high reasoning, and `service_tier=priority`;
5. have no minute-scale or fixed elapsed-time liveness timeout;
6. preserve the raw JSON event stream so the last `agent_message` is recoverable;
7. reserve both one detached-job unit and one model-invocation unit before launch; and
8. use the installed all-signals-flat liveness protocol.

The wrapper MUST reject any descriptor or argv that asks Codex to read the repository through its
sandbox on this host. The refusal remains mandatory until a separate host-fix artifact demonstrates
that `bwrap: loopback: Failed RTM_NEWADDR` is gone, the repository-reading form passes isolation
tests, and the control-plane change receives fresh authorization. An implementer may not “simplify”
the wrapper back to the broken form.

### 4.7 Iteration ledger and budget accounting

An iteration begins only after its iteration-budget and initial model-invocation reservations are
durably committed and before prompt delivery. Waiting for a long consultation does not end it before
its absolute wall-clock deadline and has no minute-scale job timeout. CLI exit or reboot leaves the
open record durable. Terminal success or failure produces one immutable canonical entry linked to
the previous SHA-256.

Schema:

```json
{
  "schema_version": 1,
  "loop_id": "activation UUID",
  "sequence": 17,
  "iteration_id": "UUID",
  "iteration_kind": "NORMAL or LIVENESS_PROBE",
  "previous_entry_sha256": "hex or null",
  "started_at": "RFC3339 UTC",
  "wall_clock_deadline": "RFC3339 UTC",
  "ended_at": "RFC3339 UTC",
  "trigger_events": [
    {
      "event_id": "UUID",
      "type": "JOB_COMPLETED",
      "sha256": "hex"
    }
  ],
  "picked": {
    "request_id": "R23",
    "plan_ref": "PLAN-006",
    "spec_ref": null,
    "incumbent_ref": "git SHA or artifact digest",
    "summary": "bounded work item"
  },
  "intent": {
    "hypothesis": "what should change and why",
    "mechanism": "bounded action",
    "expected_artifact_types": ["PLAN_REVISION"],
    "success_predicate": "falsifiable outcome"
  },
  "actions": [
    {
      "action_id": "UUID",
      "kind": "BROKER_OPERATION or DETACHED_JOB or MODEL_INVOCATION",
      "started_at": "UTC",
      "ended_at": "UTC or null",
      "job_id": "UUID or null",
      "invocation_id": "UUID or null",
      "result_ref": "path or URI",
      "result_sha256": "hex"
    }
  ],
  "pauses": [
    {
      "kind": "USAGE_RESET",
      "start": "UTC",
      "end": "UTC",
      "evidence_ref": "path"
    }
  ],
  "outcome": {
    "status": "SUCCESS or FAILED",
    "summary": "actual result",
    "validator_version_sha256": "hex"
  },
  "artifacts": [
    {
      "type": "PLAN_REVISION",
      "identity": "PLAN-006/revision-3",
      "plan_id": "PLAN-006",
      "path_or_uri": ".orchestrator/plans/PLAN-006.md",
      "before_sha256": "hex or null",
      "after_sha256": "hex",
      "validator": "plan-v1",
      "validation_receipt_sha256": "hex"
    }
  ],
  "failure": {
    "class": "NO_DURABLE_DELTA or ITERATION_WALL_CLOCK_EXCEEDED or null",
    "fingerprint": "hex or null",
    "diagnosis": "mechanical and agent diagnosis",
    "evidence_refs": ["path"]
  },
  "resources": {
    "claude_session_id": "UUID",
    "grant_id": "UUID",
    "iteration_reservation_id": "UUID",
    "initial_model_invocation_reservation_id": "UUID",
    "iterations_opened": 3,
    "iteration_limit": 12,
    "detached_jobs_launched": 1,
    "detached_job_launch_limit": 6,
    "model_invocations_admitted": 4,
    "model_invocation_limit": 18,
    "exact_session_resumes_in_iteration": 1,
    "exact_session_resume_limit_per_iteration": 3,
    "same_plan_revision_count": 2,
    "same_plan_revision_streak_limit": 3,
    "agent_restarts": 0,
    "liveness_probes_in_anomaly": 0
  },
  "next_step": {
    "disposition": "READY, WAIT_JOB, WAIT_RESET, WORK_EXHAUSTED, OPERATOR_BLOCKED, BUDGET_EXHAUSTED, VALUE_FLOOR, or STOPPED",
    "summary": "concrete next action",
    "required_event_or_artifact": "typed condition or null"
  },
  "entry_sha256": "SHA-256 with this field omitted"
}
```

Failure fingerprints hash the class, normalized subsystem/operation, stable exit or validator code,
and evidence signature. Timestamps and free-form prose are excluded so rewording cannot evade the
breaker.

The installed controller—not Claude—writes entries and budget records. The agent’s mount makes
ledger/state/budget files read-only. A verification command recomputes every digest and sequence.
Corruption stops the loop. Clean stops or daily checkpoints persist `chain.head` into the tracked
evidence area, but checkpoints never count as iteration progress or value-floor reset.

#### Budget meters

For grant G:

- `iterations_opened(G)` is the number of distinct iteration UUIDs with a committed reservation
  under G.
- `detached_jobs_launched(G)` is the number of distinct job UUIDs with a committed launch
  reservation under G.
- `model_invocations_admitted(G)` is the number of distinct invocation UUIDs with a committed
  model-invocation reservation under G.

A model invocation is any action that can initiate or resume provider-backed model computation,
including:

1. initial Claude prompt delivery;
2. Claude process start or exact-session resume after exit/reboot;
3. recognized-reset exact-session resume;
4. liveness-probe resume;
5. `codex-consult`;
6. every worker attempt or model-bearing remediation attempt; and
7. any future provider-backed job kind.

A detached model job consumes both a detached-job reservation and a model-invocation reservation.
The two reservations are committed atomically before unit creation. A worker dispatch cannot be
represented only as `BROKER_OPERATION`; the dispatcher requires the bound dual-reservation receipt.

An action is admissible only when every applicable pre-action counter is below its limit. The
reservation and counter increments occur in the same serialized durable state transaction. Retries
using the same UUID are idempotent only for state reconciliation; they cannot repeat an external
model invocation. A genuinely new launch/resume requires a new invocation UUID and consumes a new
unit.

An iteration consumes a unit even if prompt delivery, Claude startup, or validation later fails.
Its initial prompt also consumes a model-invocation unit. A detached-job launch and model-invocation
reservation remain consumed even if unit creation or the job later fails. This makes the meters
conservative and prevents crash/retry patterns from creating free spend.

Before replaying an ambiguous start or prompt, the controller reconciles the reservation’s launch
nonce, unit identity, process start time, session ID, pane sequence, hook sequence, and stream
offset. If it cannot prove that invocation did not occur, the reservation remains consumed and the
same prompt is not replayed. Any later authorized resume uses a new invocation UUID and counts
against the per-iteration resume bound.

A limit of zero disables that action class. For every positive limit:

1. if the limit is one, activation emits an immediate “single unit available” warning;
2. otherwise, the first decrement that leaves one unit remaining or reaches at least 90% consumed,
   whichever occurs first, emits a single `BUDGET_NEAR_EXHAUSTION` event and updates
   `ATTENTION.json` with severity `warning`;
3. the decrement that reaches the ceiling emits `BUDGET_EXHAUSTED` and latches “no further
   admissions”;
4. an already-admitted iteration or job may reach its evidence-preserving safe boundary, but no new
   iteration, job, broker side effect, model invocation, or probe may start;
5. at that boundary the controller enters `STOPPED_BUDGET`, stops the agent, and waits for a new
   operator grant.

Grant expiry applies the same no-new-admissions latch. Already-running detached jobs are handled by
the grant’s explicit expiry policy, defaulting to evidence-preserving cancellation at the next safe
checkpoint; expiry never grants an implicit extension.

#### Finite iteration runtime and exact-session bounds

At iteration admission, the controller writes the immutable absolute deadline
`started_at + iteration_wall_clock_ceiling`. The default is four hours. Restart, reboot, usage wait,
job wait, Stop-hook loss, or session resume does not move it.

When the deadline is reached:

1. no further prompt or resume is admitted for that iteration;
2. pane, hook, session, cgroup, event, reservation, and deferred-condition evidence is captured;
3. the Claude cgroup is terminated and verified inactive;
4. the iteration is finalized as `FAILED/ITERATION_WALL_CLOCK_EXCEEDED`;
5. its prompt digest is marked permanently nonreplayable;
6. a live progressing detached job remains independently registered and watched;
7. a recognized reset deadline remains durable; and
8. later job completion or reset requires a new iteration plus a new model-invocation reservation.

Each actual exact-session resume increments the iteration’s resume count and consumes a grant-wide
model-invocation unit. The default limit is three. Reaching it produces
`SESSION_RESUME_BOUND_REACHED`, captures evidence, and stops further recovery for that iteration.
An idempotent status reconciliation does not increment the count because it does not start or prompt
a model.

### 4.8 Progress validator and value floor

At iteration start, the controller records identities and digests in each allowlisted artifact
namespace. At Stop, the installed validator independently enumerates candidates and calls the
matching type validator.

Success requires at least one artifact that:

1. did not exist at start or has a different semantic digest;
2. remains durably present after fsync;
3. belongs to the iteration’s approved scope;
4. passes its schema and semantic transition rules;
5. has a recorded receipt.

Initial allowed delta types:

1. `PLAN_REVISION`: template-valid plan, expected ID, incremented revision, consistent frontmatter,
   and a semantic change outside generated provenance/checkpoint fields.
2. `VERDICT`: schema-valid digest-bound PASS/BLOCK or review verdict with reviewer/model identity,
   reviewed digest, reasons, and evidence.
3. `DECISION_RECORD`: new/revised decision with trigger, authority, inputs, decision, and evidence
   digests.
4. `PR`: broker receipt confirmed against the remote API, targeting integration, with immutable PR
   number/URL, head SHA, base SHA, and reviewed attempt identity.
5. `REQUEST_LEDGER_TRANSITION`: parsed row whose status or completion evidence validly changed and
   references a real artifact.
6. `SPEC_OR_ATTEMPT_RECORD`: schema-valid spec, finalized attempt manifest, escalation, or
   integration record produced by the installed dispatcher with normal bindings.
7. `OPERATOR_VISIBLE_DELIVERABLE`: an independently receipted deliverable published to the
   grant-authorized operator-facing sink with immutable identity, scope binding, content digest, and
   delivery acknowledgement.

Unknown types do not count. Deletion does not count without an allowlisted tombstone decision.

The following never count:

- test output;
- raw logs or raw pane transcripts;
- state or event files;
- job manifests or job records;
- health samples;
- alerts or `ATTENTION.json`;
- PENDING/NEXT prose;
- budget records;
- liveness-probe records;
- controller-recovery records;
- job-liveness samples;
- outer-loop ledger entries or checkpoints;
- timestamp-only, digest-only, formatting-only, or generated-provenance rewrites.

If Stop arrives while a registered job remains live, the iteration enters `WAITING_JOB` instead of
being validated unless its wall-clock deadline has expired. Otherwise, zero valid deltas produces
`FAILED/NO_DURABLE_DELTA`, `ATTENTION.json`, and `DIAGNOSING`. The diagnosis event includes the
baseline, changed noncounting files, expected artifact types, and hook/pane evidence. A repeated
identical ordinary fingerprint opens the repeated-failure breaker.

Validator exception, writable-validator detection, or validator/schema digest mismatch is
`VALIDATOR_COMPROMISED` and stops immediately.

#### Machine-checkable value floor

The controller maintains durable state
`unshipped_plan_revision_count[normalized_plan_id]`. It is derived from validation receipts and
externally meaningful transition receipts, not prose, adjacency, iteration success, or the presence
of companion artifacts.

After every finalized iteration, the controller evaluates its complete set of allowlisted validation
receipts:

1. For every normalized `plan_id` with one or more valid `PLAN_REVISION` receipts, increment that
   plan’s count once for the finalized iteration.
2. A `PLAN_REVISION` counts even when the iteration also contains a `VERDICT`,
   `DECISION_RECORD`, another plan revision, a failure record, a recovery record, or another
   counting artifact.
3. Failed/no-delta iterations, liveness probes, classifier-recovery iterations, job waits, usage
   waits, and revisions of another plan ID neither increment nor reset a plan’s count unless they
   themselves contain a validated revision of that plan.
4. A self-produced verdict or decision record about the loop’s plan, challenge, authorization
   process, or value-floor state does not reset any count.
5. Opening a PR does not by itself reset the count. The PR must reach a validated merged state.
6. A spec creation or worker launch does not reset the count. The attempt must reach a terminal gate
   outcome recorded by the installed dispatcher.
7. An intermediate request-ledger edit does not reset the count. The row must reach `done` or
   `blocked` with valid completion/blocking evidence.
8. An operator-visible deliverable resets only when the installed validator verifies its immutable
   external identity, content digest, authorized destination, and delivery acknowledgement.
9. A qualifying external transition must carry a causal scope binding to the plan ID, request ID, or
   work item whose counter it resets. Unrelated shipment cannot reset another plan’s count.

The only reset classes are therefore:

- `MERGED_PR`;
- `ATTEMPT_TERMINAL_GATE_OUTCOME`;
- `REQUEST_LEDGER_DONE`;
- `REQUEST_LEDGER_BLOCKED`; and
- `OPERATOR_VISIBLE_DELIVERABLE`.

When a reset receipt and a plan revision occur in the same iteration, the validator uses their
immutable causal ordering. A transition that ships the work represented by the revision may reset
the prior count; a later plan revision begins a new count at one. If ordering or causal binding is
ambiguous, the conservative result applies: the revision counts and no reset occurs.

When a plan’s count reaches `same_plan_revision_streak_limit`, the current iteration may be recorded
as successful, but the controller immediately emits `VALUE_FLOOR_REACHED`, writes
`ATTENTION.json`, stops the agent, and enters `STOPPED_VALUE_FLOOR`. No next iteration may open.

The default and recommended limit is 3. Activation refuses values below 2 or above 5 without a
separately authorized policy exception. A new activation or grant does not silently reset the
counter. A new operator grant may reset it only by explicitly carrying a value-floor disposition;
the disposition itself is operator action, not a model-produced `VERDICT` or `DECISION_RECORD`.

### 4.9 Stopping and circuit breakers

The agent submits exactly one typed next-step disposition at Stop. The controller validates it:

- `WAIT_JOB` requires a live registered job that has not reached `STOPPED_JOB_WEDGE`.
- `WAIT_RESET` requires recognized limit evidence and a persisted deadline.
- `READY` requires eligible in-scope work and remaining iteration and model-invocation budget.
- `OPERATOR_BLOCKED` must name the exact decision, approval, credential, or external action.
- `WORK_EXHAUSTED` requires no eligible ledger request or pending event.
- `BUDGET_EXHAUSTED` is computed from the activation grant, never accepted merely because the agent
  claims it.
- `VALUE_FLOOR` is computed from revision and external-transition validation receipts, never agent
  prose.
- `JOB_WEDGE`, `CONTROLLER_RECOVERY_STOP`, `ITERATION_WALL_CLOCK_EXCEEDED`, and
  `SESSION_RESUME_BOUND_REACHED` are machine-derived and cannot be cleared by the agent.

Breakers:

- two consecutive finalized ordinary failures with the same fingerprint;
- three unplanned agent exits in sixty minutes;
- two confirmed wedges of the same open iteration or recovery chain;
- three unsuccessful classifier-independent probes in one anomaly chain;
- four consecutive all-signals-flat detached-job windows by default;
- three failed controller recovery attempts in sixty minutes by default;
- iteration, detached-job, or model-invocation budget exhaustion;
- per-iteration exact-session resume limit;
- admitted-iteration wall-clock deadline;
- activation-grant expiry;
- same-plan unshipped revision count reaching N;
- invalid ledger or budget chain;
- installed policy/validator digest mismatch;
- unrecovered ambiguous usage/liveness protocol;
- invalid event schema;
- broker invariant failure;
- HALT.

Classifier-recovery attempts use their dedicated maximum-three breaker so the first unmatched vendor
wording change can receive bounded probes without being prematurely collapsed into an ordinary
two-fingerprint stop. They remain fully charged to iteration and model-invocation budget.

A stop atomically records state, writes timestamped alert evidence and
`.orchestrator/outer-loop/ATTENTION.json`, warns in the systemd journal, stops the affected agent or
job cgroup, and leaves the quota-free controller listening. The controller-recovery breaker uses the
heartbeat’s independent atomic alert path because the controller cannot be trusted to perform that
write.

`ATTENTION.json` includes severity, reason, evidence paths/digests, current request/iteration/session/
grant/job/invocation identities, all budget counters, exact resume precondition, classifier match
status when relevant, job stall samples when relevant, controller recovery attempts when relevant,
and whether agent/jobs were stopped.

Stopped states never spin. Resume requires the qualifying event or an explicit disposition-bearing
operator command. Removing HALT, editing a pane, waiting for another heartbeat, producing a
self-referential verdict, or restarting a stopped unit is insufficient.

### 4.10 Safety and revocation

The persistent `--dangerously-skip-permissions` process is a standing code-execution capability and
must not inherit the operator’s ambient account.

The agent service uses:

- private HOME, tmp, and dedicated tmux socket;
- `NoNewPrivileges`;
- empty capability bounding/ambient sets;
- private devices;
- strict system/kernel/cgroup protection;
- resource ceilings;
- restricted address families;
- explicit read/write mounts;
- an installed absolute initial Claude entrypoint bound to a committed invocation receipt;
- a post-start executable allowlist and restricted `PATH` that exclude Claude, Codex, worker model
  entrypoints, provider CLI aliases, repository copies, and their runtime package entrypoints.

It hides:

- the operator’s `.ssh` and GitHub configuration;
- `GH_TOKEN`, `GITHUB_TOKEN`, and `SSH_AUTH_SOCK`;
- Codex configuration/token;
- the user-systemd bus;
- installed controller, validator, ledger, and budget state;
- unrelated home, `/root`, and `/srv` paths;
- sudo capability.

The minimum Claude credential/config is bound read-only; mutable Claude cache/session data uses the
private HOME. The controller-owned runner starts the admitted session before applying the final
post-start model-entrypoint restrictions. Once Claude is running, neither its shell/tool subprocesses
nor repository code can execute the Claude/Codex/worker entrypoints again.

Enforcement must cover:

1. lookup through `PATH`;
2. known absolute installed paths;
3. symlink, hardlink, and copied-entrypoint attempts;
4. package-manager shims and shell aliases;
5. direct invocation of the CLI’s underlying runtime script/package;
6. repository-provided binaries with the same role; and
7. Codex or worker wrappers capable of reaching a provider.

The implementation may use systemd execution-path restrictions, a private mount namespace, hidden
runtime package paths, an installed one-shot launcher, and an allowlisted tool-execution wrapper.
The effective negative tests are authoritative. If the installed CLI cannot remain functional while
these paths are blocked, activation fails; the controller may not silently accept unmetered
recursion.

The agent can read and potentially exfiltrate its own Claude credential and exposed repository
content, modify writable checkout files, and consume network/quota through the already admitted
Claude session. That unavoidable residual is explicit. It cannot, by design and negative test,
start another model client, access GitHub/SSH/Codex credentials, access the user bus or installed
safety plane, touch remote main, or reach unrelated filesystem paths.

Credentialed operations use a typed controller broker, never arbitrary shell. The broker:

- rechecks HALT, grant, expiry, `autonomy_mode`, scope, and applicable budgets;
- invokes the installed parent dispatcher;
- records inputs and result digests;
- rejects source/target main;
- rejects autonomous trust-critical merge;
- rejects absent/invalid high-risk approval;
- rejects high-risk dispatch under `full_except_high_risk_dispatch`;
- rejects all worker dispatch and PR operations under `night_plans_reviews_research`;
- treats unclassified paths as high risk;
- rejects any operation that can start a model unless it carries the required model-invocation
  receipt; and
- requires a detached-job receipt as well for every worker dispatch.

`scripts/outer-loop halt` is the instant revocation command. It creates HALT first, stops the agent
and registered job units, verifies inactive cgroups, and records `HALTED`. Manual fallback is:

```sh
touch /home/val/orchestrator/.orchestrator/HALT
systemctl --user stop orchestrator-outer-agent.service
```

Removing HALT does not resume. Suspected compromise additionally requires Claude credential
revocation/rotation.

### 4.11 Codex route around bwrap

The loop does not wait for a host sandbox fix and does not change the AppArmor sysctl.

For every `codex-consult` job, the controller:

1. resolves every context file outside the model job;
2. bounds size, strips secrets, concatenates complete context with path/digest headers, and hashes
   stdin;
3. rejects any descriptor requesting repository-reading sandbox access;
4. atomically reserves one detached-job unit and one model-invocation unit;
5. starts an independent hardened systemd job with disposable HOME/workdir, only its Codex
   credential/config, and no repository/operator-home mount;
6. invokes the proven stdin/inlined-context command form with `gpt-5.6-sol`, high reasoning, and
   `service_tier=priority`;
7. applies no minute-scale or fixed elapsed-time liveness timeout;
8. samples CPU, raw JSON stream, response/output, and progress metadata under the conservative
   all-signals-flat protocol;
9. records response, raw JSON stream, stderr, exit metadata, and SHA-256 receipts; and
10. emits `JOB_COMPLETED`.

Recovering and fixture-testing the working PLAN-005 attempt-3 argv is an activation precondition. If
that invocation cannot be reproduced inside the external systemd boundary, `codex-consult` remains
disabled and any grant requiring it is refused.

Repository-reading sandbox mode is explicitly REFUSED while this host produces
`bwrap: loopback: Failed RTM_NEWADDR`. Fixing AppArmor or re-enabling that mode is a separate
high-assurance decision requiring new evidence and authorization.

### 4.12 Alternatives considered

**A. Periodic `claude -p --continue` with babysitting.**  
Still turn-scoped. It must keep a paid turn alive for hours or rely on another clock. It preserves
the fatal lifetime mismatch, adds orientation cost, and cannot represent durable idle health.
Rejected.

**B. tmux-resident Claude with a shell watchdog.**  
Fixes PTY liveness, but tmux is not an event broker, validator, ledger, budget authority,
capability boundary, or boot reconciler. Pane/process checks alone can still waste windows silently.
The selected design retains tmux but assigns supervision and policy to systemd/controller. Rejected
as the final design.

**C. Event-triggered one-shot `claude -p --resume`.**  
Better than the timer, but a turn still cannot receive the completion of work it launches, event
startup repeatedly rehydrates context, and exact background behavior remains fragile. Rejected.

**D. Cloud schedules/routines.**  
Cannot operate the on-box systemd/isolation/trust-critical lane without a new remote control surface.
May complement CLOUD-SAFE work later, but cannot satisfy R23. Rejected.

**E. Treat the version-pinned usage classifier as authoritative.**  
Spoof-resistant fixtures would protect integrity but not liveness under upstream CLI wording drift.
The result could be another silent multi-hour stall. Rejected. The selected design retains the
classifier for precise reset scheduling but adds raw-evidence alerts and bounded exact-session
probes.

**F. Meter provider tokens or vendor quota.**  
Would require unstable or unavailable vendor APIs and still fail to bound controller behavior
uniformly across Claude, Codex, and worker jobs. Rejected. Iteration, detached-job, and
model-invocation admissions are stable, local, and machine-countable.

**G. Give detached model jobs a fixed short timeout.**  
Would kill valid multi-hour SOL work solely because it is slow and would violate the standing
consultation policy. Rejected. The selected all-signals-flat protocol permits indefinitely long
advancing work while bounding genuinely stalled windows.

**H. Let the heartbeat only report a stale lease.**  
Leaves recovery dependent on the operator and fails when the controller holds its flock while hung.
Rejected. The independent heartbeat owns a separate durable alert path, cgroup recovery, lease
verification, and bounded loud-stop.

**I. Treat every schema-valid verdict or decision as shipment.**  
Allows the loop to reset the value floor using commentary about its own plans. Rejected. Only
independently validated external transitions reset the per-plan counter.

The hybrid wins because it separates deterministic liveness, validation, budgets, state, and safety
from model reasoning while preserving a genuinely live interactive runtime.

## 5. Affected boundaries & consumers

1. CLAUDE.md autonomy, HALT, bootstrap, trust closure, review independence, approval, quota, merge,
   and main-promotion rules.
2. Activation-grant schema and operator decisions about autonomous work between sessions.
3. REQUEST-LEDGER, plans, specs, verdicts, decisions, approvals, attempts, escalations, external
   transition receipts, and their schemas.
4. `scripts/dispatch.py` and installed dispatcher commands for reconcile, launch, health, cancel,
   push, PR, merge, integration, and model-invocation receipt verification.
5. systemd user manager, linger, cgroups, tmux, journal, filesystem atomicity, clocks, controller
   lease recovery, and reboot.
6. Claude version/session/hooks/usage output and Codex stdin/JSON-stream/liveness protocols.
7. Claude, Codex, GitHub, SSH, and systemd credentials, executable paths, and network boundaries.
8. Integration target, protected main, PR bindings, candidate versus installed control-plane code.
9. Event, job, health, budget, invocation, ledger, alert, heartbeat-recovery, checkpoint, and
   retained attempt evidence.
10. Repository tests/CI and host-only lifecycle/security drills.
11. Operator submit/status/read-only attach/halt/resume/install/grant workflows.

The transitive trust closure includes every parser, schema, library, config, entrypoint, classifier,
hook, unit template, installer, broker, validator, budget reservation, liveness sampler, heartbeat
recovery action, and state transition affecting these behaviors. Unknown dependencies fail high-risk.

## 6. Ordered implementation steps

1. Verify R23 evidence, absence of deleted units, CLI versions/help, PLAN-005 attempt-3 stdin
   command, systemd/linger/tmux, HALT, autonomy, branch protection, and credential paths. Replace
   §2 citations with path:line or evidence digest.
2. Add event, state, activation-grant, grant-counter, budget-reservation, model-invocation,
   detached-job-liveness, heartbeat-recovery, job, open-iteration, finalized-ledger,
   artifact-receipt, external-transition-receipt, alert, anomaly-chain, and capability schemas plus
   disabled tracked policy and canonical fixtures.
3. Implement atomic state, locking, durable events, replay, transitions, injectable clock, ledger
   verification, grant-window counters, warnings, expiry, alerts, status, halt/resume, and startup
   reconciliation.
4. Implement iteration, detached-job, and model-invocation reservations with UUID idempotency,
   pre-action decrement, near-exhaustion warning, no-overrun admission, and safe-boundary
   `STOPPED_BUDGET`.
5. Implement invocation launch nonces, ambiguous-delivery reconciliation, per-iteration exact-session
   resume counts, and the finite four-hour-default iteration deadline.
6. Implement the closed artifact-validator registry and baseline/receipt logic using installed-parent
   schema parsers.
7. Implement per-plan unshipped revision counters, external-transition reset receipts, and
   `STOPPED_VALUE_FLOOR`, default N=3. Prove self-produced verdict/decision companions, failures,
   probes, and other plan IDs cannot reset a counter.
8. Implement named detached jobs, independent units, atomic terminal manifests, manifest/event
   persistence before notification, exactly-once reconciliation, and reboot interruption.
9. Implement detached-job sampling for unit state, CPU, JSONL/raw-stream growth, output growth, and
   progress-file mtimes; add two-sample `JOB_OVERDUE`, four-window-default
   `STOPPED_JOB_WEDGE`, evidence capture, cgroup termination, and progress-resumed reset.
10. Implement explicit Claude session identity/resume, dedicated tmux socket, pipe-pane logging, safe
    buffer delivery, Stop hook, and controller-owned invocation receipts.
11. Implement primary usage parsing plus raw-pane capture, classifier-mismatch alerts, the
    thirty-minute bounded liveness-probe schedule, its iteration/model reservations, and terminal
    unclassified stop.
12. Add controller, agent, heartbeat, job watcher, and job unit templates plus installer/uninstaller.
    Units point at the authorized installed snapshot, not mutable repository code. Use
    `Restart=always` for the controller.
13. Implement the heartbeat’s controller-independent lease/recovery namespace and lock, stale-cgroup
    termination, explicit controller start/restart, lease-advance verification, bounded recovery
    breaker, standalone loud-stop sentinel, and direct agent/job shutdown.
14. Implement filesystem/credential isolation and the typed capability broker. Enforce both
    `autonomy_mode` values, prevent recursive model entrypoints, require worker dual-reservation
    receipts, and add negative security tests before any live model start.
15. Implement `codex-consult` using the recovered stdin/inlined-context invocation, dual admission,
    external systemd isolation, raw-stream preservation, and all-signals-flat liveness sampling.
    Hard-reject repository-reading sandbox descriptors and do not change AppArmor.
16. Add deterministic tests for schemas, state, chain corruption, replay, usage parsing/spoofing,
    parser drift, raw evidence, probe scheduling, all budget meters, resume idempotency, iteration
    deadlines, job overdue/wedge recovery, controller recovery, warning thresholds, value floor,
    reset/reboot, detached completion, no-delta validation, breakers, HALT races, capability denial,
    autonomy modes, recursive-model refusal, broken Codex-form refusal, and candidate
    self-activation.
17. Update AGENTS.md, CLAUDE.md, and operator runbook with runtime, supported input, state/alerts,
    grant modes, all counters, iteration deadlines, resume bounds, job liveness, heartbeat recovery,
    value floor, revocation, residual risk, CLI upgrade, Codex workaround, evidence, and recovery.
18. Run `./scripts/test`, actual-unit security tests, CLI/hook/session smoke tests, recursive-model
    negative tests, classifier-drift fixture, stalled/advancing detached-job canaries, and controller
    kill/hang recovery drills. Produce bound evidence. Do not activate.
19. Submit the same revision for fresh SOL Critical review and Claude challenge under the R24
    stop-rule. Resolve findings in a new revision until both PASS, then obtain operator
    authorization.
20. Install with the agent disabled. Confirm `Linger=yes`, start only the deterministic controller
    and heartbeat, test HALT/status/spool/grant/budget/lease-recovery behavior, then enable a tightly
    scoped grant.
21. Run live drills for recognized usage reset, unrecognized usage wording, detached completion,
    advancing long Codex work, detached-job wedge, controller clean exit/hang, value-floor stop,
    all budget stops, iteration wall-clock stop, recursive invocation refusal, and exact-session
    reboot recovery.
22. Enable normal scoped operation only after the natural usage-reset and operator-approved reboot
    drills pass. Reconcile R23 and record completion conformance.

## 7. Failure modes & blast radius

| Trigger | Consequence | Mitigation |
|---|---|---|
| Controller crash or clean exit | Events temporarily undelivered | `Restart=always`, durable replay, lease heartbeat |
| Controller hangs | Active unit stops making decisions | independent alert spool, stale-cgroup kill, restart, lease verification |
| Repeated controller recovery failure | Control plane cannot be trusted to resume | durable `CONTROLLER_RECOVERY_STOP`, direct agent/job shutdown, loud alert |
| Claude exit | Runtime disappears | capture evidence before metered exact-session recovery |
| Known usage exhaustion | Work pauses until reset | first-class `WAITING_USAGE_RESET`, persisted deadline, no polling |
| Usage wording changes | Primary parser misses exhaustion | raw unparsed evidence, immediate alert, bounded thirty-minute probes |
| Repeated parser mismatch | Extra model resumes | each consumes iteration and model budget; maximum three, then loud stop |
| Reboot during reset | Work remains paused | persisted UTC deadline and boot reconciliation |
| Job finishes while controller down | Socket notification lost | manifest/event persisted first, startup replay |
| Job killed by reboot | Eternal wait | `JOB_INTERRUPTED`; fresh named retry only |
| Registered job remains live but deadlocked | `WAITING_JOB` could stall | all-signals-flat sampling, `JOB_OVERDUE`, bounded `STOPPED_JOB_WEDGE`, cgroup termination |
| Long advancing Codex consultation | False timeout could destroy valid work | no elapsed liveness timeout; any CPU/stream/output/progress advance resets stall count |
| Stop hook absent | Validator bypass risk | no success; anomaly evidence and bounded recovery/stop |
| No artifact | Silent wasted iteration | `NO_DURABLE_DELTA` alert and repeated-failure breaker |
| Repeated same-plan polishing with companion verdicts | Budget spent without shipping | persistent per-plan revision counter; companions do not reset |
| Failure/probe inserted between plan revisions | Value-floor evasion | failures and recovery iterations do not reset |
| Alternate plan IDs | One plan’s floor evaded | per-plan counters persist independently |
| Externally meaningful shipment occurs | Floor should permit new planning | validated causal reset receipt |
| Cosmetic/log change | False progress | closed semantic validators and explicit non-counting list |
| False WAIT state | Infinite idle | live registered job or recognized usage evidence required |
| Long silent valid Claude work | False kill | two samples; any CPU/output/job progress prevents wedge kill |
| True Claude wedge | Window stalls | two-sample confirmation; one recovery; second wedge stops |
| One admitted Claude iteration runs forever | One unit permits unbounded spend | absolute four-hour-default deadline and forced finalization |
| Ambiguous session resume | Duplicate provider invocation | invocation UUID, launch nonce, conservative consumption, no same-ID replay |
| Recursive Claude/Codex invocation | Model spend bypasses controller | post-start executable restrictions and activation-blocking negative tests |
| Worker dispatch bypasses job meter | Unbounded worker model calls | every dispatch requires detached-job plus model-invocation receipts |
| Iteration budget exhausted | Autonomous turns continue | atomic admission counter and `STOPPED_BUDGET` |
| Job budget exhausted | Detached work continues | atomic launch counter and `STOPPED_BUDGET` |
| Model budget exhausted | Hidden resumes/worker calls continue | atomic invocation counter and `STOPPED_BUDGET` |
| Grant expires | Old authority remains active | no-new-admissions latch and explicit stopped state |
| Counter write torn | Free or double spend | fsync/rename, UUID reservations, reconciliation, fail closed |
| Torn ledger write | Lost/corrupt memory | fsync/rename/hash chain; fail closed |
| Candidate alters validator | Self-approval | active installed snapshot is read-only |
| Agent exfiltrates secrets | Credential compromise | expose only Claude credential; halt and rotate |
| Agent damages checkout | Local corruption | disposable/scoped work area, broker/gates/review |
| Broker ignores autonomy mode | Unauthorized night action | installed-parent enforcement and negative tests |
| Broker permits main/high-risk merge | Trust-boundary breach | installed-parent deny, approval checks, branch ruleset |
| HALT race | Side effect after stop | HALT-first, immediate pre-side-effect recheck, cgroup stop |
| Heartbeat misfires | Unneeded model start | heartbeat cannot invoke a model; it only recovers deterministic units |
| Grant too broad | Excess work/quota | explicit mode, scope, three ceilings, finite iteration runtime, expiry, approval |
| tmux dies | Session loss | systemd report and metered exact-session/ledger recovery |
| bwrap remains broken | Consult failure | mandatory stdin context; repository sandbox form refused |
| Hardening unsupported | Excess host access | activation-blocking verification and negative probes |

Worst credible case is arbitrary command execution within the Claude unit’s exposed filesystem and
network, exfiltration of its Claude credential/repository content, local checkout damage, and
consumption through the already admitted Claude invocation up to its finite iteration deadline.
The design keeps GitHub/SSH/Codex/systemd credentials and the installed safety plane outside that
unit, denies recursive model entrypoints, and bounds all controller-authorized model starts with
grant reservations, but does not claim `--dangerously-skip-permissions` is harmless.

Recovery is HALT, stop all units, revoke Claude credentials, preserve evidence, audit remotes,
recreate the control checkout, reinstall the last authorized snapshot, and remain disabled pending
a new Critical authorization.

Irreversible effects are model quota/cost and data already transmitted to provider APIs.

## 8. Validation plan (falsifiable)

Deterministic tests use fake Claude/Codex binaries, injectable time, disposable state, and
systemd/tmux adapters. Host-bound tests repeat lifecycle and security checks with real units.

1. **Recognized usage exhaustion:** fake Claude starts as S1, opens an iteration with iteration and
   model reservations, emits a captured recognized limit record, and exits or waits. Before reset,
   assert zero model calls. At reset, assert immediate exact resume of S1 and the same iteration,
   with a new model-invocation reservation, no crash/failure count, and one resume-count increment.
   Restart the controller during the wait. Also place reset beyond the iteration deadline and assert
   the old iteration finalizes, no stale prompt is replayed, and reset later opens a newly reserved
   iteration. The old fixture fails because `claude -p` exits and continuation depends on a later
   timer. A natural live limit/reset is required before completion.
2. **Classifier drift:** alter the fake CLI wording so no classifier fixture matches. Assert raw,
   pre-normalization pane evidence is retained and digest-bound; `ATTENTION.json` immediately names
   the mismatch; no `WAITING_USAGE_RESET` transition occurs; no probe occurs before the eligibility
   deadline; probes occur no more frequently than every thirty minutes; every probe resumes S1 and
   consumes a new iteration unit and model-invocation unit; a valid Stop or recognized message
   cancels the schedule; and three unmatched probes produce `STOPPED_UNCLASSIFIED`. Assert there is
   no indefinite idle state.
3. **Probe budget interaction:** leave only one iteration unit or one model-invocation unit at
   anomaly time. Assert exactly one eligible probe may open when both meters permit it, applicable
   counters reach their ceilings, no second probe occurs, and the controller reaches
   `STOPPED_BUDGET` with raw anomaly and budget evidence.
4. **Detached completion while idle:** launch a fake independent job, let Claude enter
   `WAITING_JOB`, then complete it. Assert applicable budget reservations, manifest-before-event,
   delivery within five seconds, exact-session receipt, and one successful iteration. Repeat with
   controller down. The old fixture fails because no live process receives completion.
5. **Detached-job liveness:** launch a fake registered job whose unit remains active while CPU,
   stream, output, and progress mtimes are all flat. At the first sample assert no alert. At the
   second consecutive flat sample assert `JOB_OVERDUE`, warning evidence, and no termination. At the
   fourth flat window assert final evidence capture, graceful-then-forced cgroup termination,
   `JOB_INTERRUPTED/JOB_WEDGE`, and `STOPPED_JOB_WEDGE`. Advance each signal independently in
   controls and assert every advance resets the stall counter. Run an advancing fake
   `codex-consult` beyond four hours and assert it survives.
6. **Reboot:** persist an open iteration, all counters, queued event, S1, job liveness samples, and
   waiting state; kill all processes; restart the service harness. Assert chain verification,
   counter reconciliation, exactly-once delivery, and S1 continuation only with a new invocation
   reservation where required. Then perform an operator-approved actual VPS reboot with
   `Linger=yes`. The old fixture has no explicit session/open-iteration recovery.
7. **Controller clean exit:** make the controller exit zero. Assert `Restart=always` creates a new
   instance and advances the lease without model invocation.
8. **Controller hang:** hold the controller flock and stop lease advancement while leaving the unit
   active. Assert the heartbeat independently persists `CONTROLLER_LEASE_STALE`, does not wait for
   the controller flock, kills the whole stale cgroup, restarts the controller, and verifies a new
   lease sequence. Make three recoveries fail within sixty minutes and assert standalone
   `CONTROLLER_RECOVERY_STOP`, severity-stop evidence, and direct shutdown of controller, agent, and
   registered jobs.
9. **Claude wedge:** fake an active process with no output, CPU, hooks, or jobs. First sample does not
   kill; second confirms the wedge and captures raw evidence. Assert bounded, separately metered
   exact-session recovery. A second wedge opens the breaker. CPU/output/job-progress controls must
   survive. The old fixture has no confirmed-hang logic.
10. **Iteration wall-clock ceiling:** keep fake Claude busy with advancing CPU/pane data beyond the
    configured four-hour deadline. Assert the deadline is not extended by progress, restart, wait,
    or resume; the Claude cgroup is terminated; the iteration records
    `FAILED/ITERATION_WALL_CLOCK_EXCEEDED`; and its prompt cannot be replayed. Associate an
    independently advancing detached job and assert that job remains alive and monitored.
11. **Resume idempotency:** crash before and after every resume reservation, launch marker, process
    start, prompt delivery, and post-delivery observation. Assert a reservation UUID causes at most
    one actual launch/prompt, uncertainty consumes the unit, a genuine later resume needs a new UUID,
    and the fourth resume under the default per-iteration limit is refused.
12. **No delta:** deliver an event and Stop while only logs/state/timestamps change. Assert
    `FAILED/NO_DURABLE_DELTA`, alert, diagnosis, and no success. Repeat identically and assert no
    third ordinary prompt. The old fixture accepts exit zero.
13. **Budget accounting:** for all three counters, crash between every
    reservation/write/launch/prompt phase and restart. Assert each UUID consumes zero or one unit,
    never more and never free; failed admissions do not exceed a ceiling; warning occurs before
    exhaustion; zero limits disable the action; and expiry blocks new admissions.
14. **Worker/model admission mapping:** request one low-risk worker dispatch. Assert the broker alone
    cannot launch it, both detached-job and model-invocation reservations commit atomically, and the
    installed dispatcher rejects a missing, mismatched, replayed, or already-used receipt. Assert
    every remediation worker requires fresh reservations.
15. **Recursive model refusal:** from the real running agent namespace, attempt `claude`, `codex`,
    known absolute paths, symlinked/copied entrypoints, package-manager shims, direct runtime-script
    execution, repository wrappers, and worker launchers. All fail before provider contact. Assert
    ordinary approved non-model tools still work. If any model path succeeds, activation fails.
16. **Value floor:** finalize three iterations containing PLAN-006 revisions and assert counts 1, 2,
    and 3 followed by `STOPPED_VALUE_FLOOR` and no fourth prompt. In separate cases insert a
    `VERDICT`, `DECISION_RECORD`, failed/no-delta iteration, liveness probe, classifier recovery,
    and PLAN-007 revision between PLAN-006 revisions; assert none resets PLAN-006’s count. Open but
    do not merge a PR and assert no reset. Then validate each allowed external transition—merged PR,
    terminal attempt gate outcome, request-ledger `done`, request-ledger `blocked`, and
    independently acknowledged operator-visible deliverable—and assert only a causally linked
    transition resets the applicable plan counter. Attempt unrelated shipment and ambiguous receipt
    ordering and assert conservative no-reset behavior.
17. **Ledger durability:** kill between each atomic-write phase; recovery yields the old or new
    complete state. Modify/delete/reorder entries or reservations and assert `STOPPED_INTEGRITY`
    before Claude starts.
18. **Event integrity:** duplicate/reorder events, lose socket notifications, and include shell
    metacharacters/fake limit text. Assert exactly-once handling, safe tmux delivery, and no spoofed
    usage transition.
19. **HALT and broker:** race HALT against prompt, job, worker, PR, and merge. Assert no action after
    the final HALT check. Requests for main, arbitrary argv, unapproved high-risk work,
    trust-critical merge, candidate validator, expired grant, unreserved model invocation, or
    unreserved worker must be denied.
20. **Autonomy modes:** under `full_except_high_risk_dispatch`, assert permitted low-risk lane
    actions work and high-risk dispatch is refused. Under `night_plans_reviews_research`, assert
    plans/reviews/research work while worker dispatch, PR creation, integration, merge, and system
    mutation are refused regardless of broader capability strings.
21. **Credential isolation:** from the real agent unit, attempt reads of SSH/GitHub/Codex
    credentials, user bus, installed validator/ledger/budgets, `/root`, and unrelated home/srv, and
    writes outside the allowlist. All fail.
22. **Codex invocation precondition:** record `claude --version`; prove Stop-hook receipt, explicit
    S1 creation and exact resume, and real limit-fixture parsing. Reproduce the PLAN-005 attempt-3
    stdin/inlined-context Codex invocation in the hardened consult unit with dual reservations.
    Submit a repository-reading sandbox descriptor and assert deterministic refusal before launch
    and before budget consumption.
23. **Stops:** exercise exhausted work, operator block, all three budget ceilings, grant expiry,
    value floor, repeated failures, crash loop, classifier mismatch, Claude wedge, detached-job
    wedge, controller-recovery failure, iteration deadline, and resume bound. Assert one
    digest-bound alert chain, no spinning, and only a qualifying resume.
24. **Suite/evidence:** `./scripts/test` passes; CI remains exactly `ci`; snapshot, grant, counters,
    policy, units, test logs, live receipts, and final ledger head are digest-bound in completion
    evidence.

The five headline tests explicitly run against both the deleted-design fixture and the replacement;
each must fail old/pass new.

## 9. Rollback / irreversibility

1. Run `scripts/outer-loop halt` and verify all controller, agent, heartbeat recovery, and job
   cgroups inactive.
2. Disable controller, agent, heartbeat, job-watcher, and related units; remove wants links;
   daemon-reload. Do not restore the old timer.
3. Remove or repoint the installed snapshot and restore the installer’s hook-config backup.
4. Disable/remove the local activation grant. Preserve ledger, reservations, counters, invocation
   receipts, events, jobs, job-liveness samples, controller-recovery records, raw pane evidence,
   logs, and alerts.
5. Rotate Claude credentials if exposure is suspected and audit GitHub/SSH/Codex access.
6. Resume manually in an operator-controlled session.

Git, unit, tmux, linger, PR, and local-state changes are reversible. Model quota and provider-bound
content are not. No kernel/AppArmor change is included.

## 10. Open questions / operator decisions

One operator decision is required in every activation grant: what the loop may do autonomously
between operator sessions.

Choose `autonomy_mode`:

1. **`full_except_high_risk_dispatch` — recommended default.** Allow all explicitly granted lanes,
   including low-risk worker dispatch and opening PRs to `integration`, except high-risk dispatch.
   High-risk work already requires a per-dispatch approval artifact the loop cannot mint and remains
   outside autonomous execution.
2. **`night_plans_reviews_research` — conservative alternative.** Allow only plans, reviews, and
   bounded research/consultation jobs. Disallow worker dispatch, PR creation, integration, merge,
   and system/remote mutation.

This choice is activation data, not a code change. The controller implements both modes and fails
closed if the field is absent or unknown.

The operator must also execute existing authority steps: authorize the final Critical digest, choose
the scope and three budget ceilings, choose the value-floor limit or accept the default of 3, accept
or replace the finite four-hour iteration ceiling, choose the exact-session resume limit or accept
the default of 3, set the grant expiry, enable linger if absent, approve the live reboot and
controller-recovery drills, and explicitly enable production operation.

## 11. Provenance (filled during challenge/authorization — NOT by the drafter)

- **Challenge (Claude):** REVISE on revision 1 — O1 and O2 blocking; O3 and O4 required amendments.
- **Adversarial stop-rule review:** BLOCK on revision 2 — B1 through B4 safety-material.
- **Claude disposition:** SUSTAINED B1 through B4 with required mechanisms.
- **Disposition (drafter):** Revision 3 accepts and amends exactly B1 through B4; see the disposition
  record below.
- **Dual-validation (high-assurance/control-plane):** SOL verdict PENDING; Claude verdict PENDING.
- **Authorization:** PENDING; no unit may be installed or enabled.
- **Completion reconciliation:** N/A — draft only; implementation has not begun.

## Disposition record (revision 3)

- **B1 — ACCEPT AND AMEND: detached-job liveness.** §§1, 3.8–3.9, 3.12, 3.23, 3.34–3.35,
  4.2–4.4, 4.6, 4.9, 4.11, 6.8–6.9, 7, 8.4–8.5, and 9 add a conservative per-job sampler for unit
  state, cumulative CPU, raw JSONL/stream growth, output growth, and progress-file mtimes. Any
  advancing signal resets the stall count. Two consecutive all-signals-flat samples at a default
  fifteen-minute job-kind-configurable interval emit `JOB_OVERDUE`, persist evidence, update
  `ATTENTION.json`, and alert. Four consecutive stalled windows by default capture the linked
  evidence chain, terminate and verify the unit inactive, record `JOB_INTERRUPTED/JOB_WEDGE`, and
  enter `STOPPED_JOB_WEDGE`. This is explicitly not a minute-scale or elapsed-runtime timeout:
  an advancing `codex-consult` survives indefinitely under the liveness rule.
- **B2 — ACCEPT AND AMEND: independent controller recovery.** §§1, 3.23, 3.30, 3.36, 4.2,
  4.3–4.5, 4.9, 6.12–6.13, 7, 8.7–8.8, and 9 change the controller unit to `Restart=always` and
  define a heartbeat-owned recovery path that never acquires the controller flock. The heartbeat
  atomically persists standalone alerts, kills a stale controller cgroup, explicitly starts or
  restarts the controller, and verifies advancement of a boot/instance/sequence-bound lease. Three
  failed recoveries in sixty minutes by default create durable `CONTROLLER_RECOVERY_STOP`, stop the
  controller, agent, and registered jobs directly, and publish a standalone severity-stop
  `ATTENTION.json`.
- **B3 — ACCEPT AND AMEND: complete model admission and finite invocation bounds.** §§1,
  2 assumptions 7, 3.2–3.5, 3.10, 3.13, 3.17–3.18, 3.22–3.23, 3.26, 3.29, 3.32, 3.37–3.39,
  4.1–4.7, 4.9–4.11, 5–7, 8.1–8.3, 8.6, 8.9–8.15, 8.19, 8.22–8.24, 9, and 10 add the
  grant-window `MODEL_INVOCATIONS` meter. Every initial Claude prompt, process start, exact-session
  resume, liveness probe, `codex-consult`, worker attempt, and model-bearing remediation reserves a
  named invocation before execution. Every worker dispatch is also a named detached job and
  atomically reserves a detached-job unit. Invocation UUIDs and launch nonces make reconciliation
  idempotent without permitting same-ID prompt replay. Exact-session resumes are separately charged
  and bounded to three per iteration by default. Every iteration receives an immutable finite
  wall-clock deadline, default four hours, after which its Claude cgroup is terminated and the
  iteration records `FAILED/ITERATION_WALL_CLOCK_EXCEEDED`; independently advancing detached jobs
  remain governed by B1. The agent’s post-start executable namespace and `PATH` exclude recursive
  Claude, Codex, worker, and equivalent provider entrypoints, with activation-blocking negative
  tests.
- **B4 — ACCEPT AND AMEND: externally meaningful value-floor reset.** §§1, 3.6, 3.20,
  3.22–3.23, 3.32, 3.40, 4.3, 4.7–4.9, 5–8.16, 9, and 10 replace the adjacent
  plan-only streak with a durable per-plan unshipped-revision count. Every validated revision of the
  same plan ID counts even when its iteration also emits a `VERDICT`, `DECISION_RECORD`, failure,
  recovery artifact, or another plan revision. Failures, probes, other plan IDs, new activations,
  and self-produced artifacts about the loop’s own plans do not reset it. Only a causally linked,
  independently validated merged PR, terminal attempt gate outcome, request-ledger transition to
  `done` or `blocked`, or acknowledged operator-visible deliverable resets the applicable count.
