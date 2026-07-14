I completed the draft, but the workspace rejected the write because this session is read-only. Intended path: [.orchestrator/plans/PLAN-006.md](/home/val/orchestrator/.orchestrator/plans/PLAN-006.md).

```markdown
---
id: PLAN-006
created: 2026-07-14
author: OpenAI Codex (GPT-5)
status: draft
ledger_ref: R23
lane: control-plane
revision: 1
supersedes: null
---

# PLAN-006 — Event-driven, durable outer loop for autonomous continuation

> **Brief-caliber standard (operator, 2026-07-13):** every plan artifact must reach the depth of the
> original SETUP-BRIEF — a standalone document detailed enough that an agent can execute it
> autonomously with NO further clarification. Not a bullet sketch. If a section is genuinely N/A,
> write "N/A because …". Codex drafts to this template; Claude challenges + authorizes; both then
> follow it.

## 1. Decision & non-goals

Implement the orchestrator’s outer loop as a hybrid, event-driven control plane. A deterministic,
quota-free Python controller runs continuously as a hardened systemd user service and owns the state
machine, durable event spool, append-only iteration ledger, budgets, validation, circuit breakers,
and privileged capability broker. A persistent interactive Claude CLI process runs in an isolated
tmux PTY as a separately hardened, controller-managed service; tmux supplies interactivity and
operator visibility but is not the supervisor.

The controller delivers durable events only while the Claude prompt is known idle, keeps an
iteration open across detached work and usage waits, and resumes the same explicit Claude session
after a CLI exit or reboot. Detached jobs run in independent systemd units and atomically publish
completion events. Usage exhaustion is a persisted WAITING_USAGE_RESET state with a deadline derived
from the already-observed CLI limit message, never a crash and never a periodic quota probe. Every
completed iteration passes through an independent allowlisted artifact-delta validator before it can
be called successful.

Activation is fail-closed, uses a separately installed authorized controller rather than mutable
candidate code, and remains subject to HALT, high-risk approval, branch, review, and merge invariants.

Non-goals:

1. This plan does not change the worker inner loop, remediation policy, gate meanings, reviewer
   independence, branch protections, or integration-to-main promotion.
2. It does not make an iteration-ledger entry proof that work is correct. The outer validator proves
   durable progress; existing specs, gates, independent review, CI, and human authorization prove
   admissibility.
3. It does not autonomously merge trust-critical work, weaken high-risk approval, touch remote main,
   or grant the model direct GitHub, SSH, Codex, sudo, or user-systemd credentials.
4. It does not restore the deleted five-hour timer or use periodic model invocation as the driver. A
   ten-minute local heartbeat is only a zero-quota liveness fallback.
5. It does not depend on changing kernel.apparmor_restrict_unprivileged_userns. Codex consultations
   route around the broken bwrap path with complete stdin context inside an external systemd
   isolation boundary.
6. It does not self-activate. Challenge, dual validation, authorization, installation, and staged
   operator-approved activation remain mandatory.

## 2. Current-state evidence (facts, with citations)

### Observed facts

1. The repository already has a bounded inner loop: schema-approved specs dispatch attempts through
   integrity, scope, test, and review gates; remediation is bounded; attempts retain evidence;
   stale-base work is refused; and main promotion is human-only. See AGENTS.md, “What this repo is,”
   and CLAUDE.md, “Definition of done,” “Remediation + integration,” and “Hard invariants.”
2. The prior continuation mechanism was a five-hour systemd user timer invoking
   continue-session.sh, which ran one-shot claude -p under a five-hour timeout. Its continuation
   decision was a PENDING baton or live-attempt scan. See the deleted script supplied in R23.
3. The timer fired at 00:36 and 05:36 UTC and both claude -p processes exited zero. Timer delivery
   therefore was not the primary failure. See the operator-supplied R23 forensics and journal
   observations.
4. The 05:36 run said it would end the turn and resume on background notifications, but claude -p
   exited with the turn and could not receive them. See
   .orchestrator/continue-logs/20260714T053621Z.log as quoted by the R23 forensics. Roughly nine
   hours produced about twelve minutes of agent work.
5. PLAN-005 Codex consultations produced empty response files and about 36 KB of stderr containing
   bwrap: loopback: Failed RTM_NEWADDR. See
   .orchestrator/decisions/PLAN-005-isolation-failopen/response.attempt1.md,
   response.attempt2.md, and their sibling stderr evidence identified in R23.
6. The deleted service had no explicit Claude session identifier, no durable hypothesis/outcome
   ledger, no detached-completion event consumer, and no artifact-delta validator. A zero exit was
   indistinguishable from useful work. See the deleted continue-session.sh and the R23 reframe table.
7. The timer/service were disabled and deleted; the script and logs were retained as evidence. They
   must not be revived. See R23, “Actions taken.”
8. Existing policy treats worker usage exhaustion as interrupted, not failed; requires a fresh worker
   attempt rather than resuming a partially modified worktree; and prohibits minute-scale SOL
   timeouts. See CLAUDE.md, “Quota / degradation policy,” and AGENTS.md, “Consulting Codex SOL.”
9. HALT is the global kill switch; high-risk dispatches require per-attempt approval; candidate
   trust-boundary code may not validate or activate itself; and main promotion is human-only. See
   CLAUDE.md, “Autonomy level,” “Execution split,” “Remediation + integration,” and “Hard
   invariants.”
10. The target is Ubuntu 24.04 with systemd --user, tmux, Claude CLI, and Codex CLI installed. The
    bwrap failure is an observed host defect caused by its user-namespace/AppArmor boundary.

### Assumptions that must become measured preconditions

1. The installed Claude CLI supports an interactive PTY, explicit session identity or exact-session
   resume, and a Stop hook. Implementation must record claude --version and pass disposable
   hook/session-resume tests. It must not silently substitute “most recent conversation.”
2. The installed CLI’s usage-limit output contains either a parseable reset instant or a stable
   exhaustion marker. Implementation must capture a sanitized real fixture and pin parsing to the
   installed version. Unknown wording fails closed.
3. The required systemd user hardening directives work on Ubuntu 24.04. systemd-analyze verify and
   negative access tests must prove the effective boundary; unsupported directives block activation.
4. The user manager starts after reboot without login. loginctl show-user must report Linger=yes
   before the reboot drill. Enabling linger is a one-time privileged operator action.
5. Repository line-level inspection could not be performed during drafting because every local
   command failed before execution with the documented bwrap RTM_NEWADDR error, and this session’s
   filesystem is read-only. Claude’s challenge must reconcile these exact file/section citations
   against the tree and replace stale paths or add line numbers before authorization.

## 3. Requirements & acceptance criteria (numbered, testable)

1. Without a valid local enable grant, or with HALT present, starting either outer-loop unit SHALL
   launch no Claude process or detached job and SHALL persist DISABLED or HALTED.
2. A submitted operator event or detached-job completion SHALL be durably spooled before
   acknowledgement and delivered to an idle healthy agent within five seconds on the test clock,
   without waiting for a heartbeat.
3. A detached job SHALL remain owned by an independent systemd unit after a Claude turn or process
   exits. Its status, output digest, and completion event SHALL survive controller downtime and be
   reconciled exactly once.
4. On a recognized usage-limit message, the controller SHALL transition the open iteration to
   WAITING_USAGE_RESET, persist the Claude session ID and reset deadline, make no model probes while
   waiting, and automatically resume that same session after reset. Usage waiting SHALL not increment
   crash or failure counters.
5. A controller restart, user-manager restart, or host reboot SHALL reconstruct state, reconcile
   units/events, and resume the same open iteration and Claude session, or enter an explicit
   fail-closed stop state. Conversation memory alone SHALL never be required.
6. Every automated turn SHALL belong to exactly one controller-created open iteration. Waiting for a
   registered job or usage reset pauses that iteration instead of closing it.
7. An iteration SHALL be SUCCESS only when the independent validator finds at least one allowlisted,
   schema-valid semantic artifact delta against its start baseline and records before/after digests
   or immutable remote identity.
8. Loop state, logs, heartbeats, job manifests, timestamps, PENDING/NEXT prose, and the iteration’s
   own ledger entry SHALL never count as progress.
9. A turn that stops without a valid delta and without entering legitimate WAITING_JOB or
   WAITING_USAGE_RESET SHALL close FAILED/NO_DURABLE_DELTA, write evidence and an operator-visible
   alert, and enter DIAGNOSING.
10. Every finalized iteration SHALL record its trigger, selected work, intent/hypothesis, actions,
    outcome, validated artifacts, failure class/fingerprint, resource counters, and typed next step.
    Entries SHALL form a SHA-256 chain; tampering or truncation SHALL stop the loop before another
    model invocation.
11. WORK_EXHAUSTED, OPERATOR_BLOCKED, LOCAL_BUDGET_EXHAUSTED, VALIDATOR_COMPROMISED,
    LEDGER_CORRUPT, two consecutive identical failure fingerprints, three agent crashes in sixty
    minutes, or two confirmed wedges of one iteration SHALL stop the agent and produce
    ATTENTION.json plus a journal warning.
12. A busy agent SHALL be declared wedged only after two consecutive ten-minute samples show all of:
    an active nonwaiting turn, no pane/log change, no CPU-time increase, no job progress, and no
    hook/event activity. A busy-but-silent process with advancing CPU SHALL survive.
13. Creating HALT SHALL prevent new side effects, stop the agent cgroup and all outer-loop-owned job
    units, and persist HALTED. Every broker action SHALL recheck HALT immediately before execution.
    Removing HALT alone SHALL not resume work.
14. The persistent Claude unit SHALL have no GitHub token, SSH key/agent, Codex credential, sudo,
    user-systemd bus, or writable installed controller/validator/ledger. Negative tests SHALL prove
    these resources inaccessible.
15. GitHub/systemd actions requested by the agent SHALL pass through an allowlisted broker using the
    installed parent dispatcher. The broker SHALL reject remote main, reject autonomous merge of
    trust-critical work, and reject absent/invalid high-risk approval.
16. Codex consultations SHALL use complete digest-bound stdin context in an externally hardened
    detached unit and SHALL not depend on Codex reading the repository through bwrap. No AppArmor
    weakening is required.
17. Controller, heartbeat, reset scheduler, job watcher, and health classifier SHALL make zero
    Claude/Codex/API calls. Only process state, hooks, systemd state, local logs, deadlines, and the
    durable spool may be used for health.
18. The heartbeat SHALL detect a dead controller lease, missed event, overdue reset deadline, or
    confirmed wedge, but SHALL not prompt an idle agent to ask for status.
19. The five regression scenarios—usage exhaustion, detached completion while idle, reboot, wedge,
    and no-delta iteration—SHALL fail against the preserved old-design fixture and pass against the
    new controller.
20. Real installed-CLI hook/session/parser smoke tests and an operator-approved actual reboot drill
    SHALL pass before R23 is marked done.

## 4. Design / approach

### 4.1 Activation and bootstrap boundary

The active loop is an installed, digest-bound control-plane snapshot, not code imported from the
mutable repository checkout. The repository contains source, schemas, tests, unit templates, and
fixtures. After authorization, an operator-only installer copies the authorized controller,
validator, schemas, prompt, and units into a versioned installation directory and records the
PLAN-006 revision digest.

The Claude service sees this installation read-only. Candidate changes therefore cannot validate,
install, or activate themselves.

Tracked policy ships disabled. A gitignored local activation grant contains:

- authorized PLAN-006 digest;
- allowed request, plan, and spec scope;
- maximum completed iterations, Codex consultations, worker dispatches, and active-turn time;
- provider-window fallback upper bound;
- allowed broker capabilities;
- expiry and operator identity.

The controller refuses missing, expired, widened, or digest-mismatched grants. WAITING_JOB and
WAITING_USAGE_RESET do not consume active-turn time.

### 4.2 Runtime components

1. orchestrator-outer-loop.service runs the deterministic controller in the foreground with
   Restart=on-failure. It owns state, events, deadlines, jobs, ledger, validation, budgets, health,
   alerts, and capability decisions. It performs no model calls.
2. orchestrator-outer-agent.service runs a small installed runner that creates an isolated tmux
   server on a dedicated socket, starts interactive Claude with a controller-assigned UUID, enables
   pipe-pane logging, and remains tied to that tmux lifecycle. It has Restart=no: the controller must
   classify the exit before any relaunch.
3. orchestrator-outer-heartbeat.timer performs zero-quota local inspection every ten minutes. It
   covers missed spool notifications, health sampling, and overdue deadlines; it is not the driver.
4. scripts/outer-loop is the client/operator interface: enable, disable, submit, status, attach,
   resume, halt, event, job submit/status, iteration inspect, and install.
5. The Claude Stop hook submits hook JSON to the installed client. It never writes state or ledger
   directly.
6. Detached work runs as orchestrator-outer-job@<job-id>.service or equivalent transient units
   created from validated named descriptors. The wrapper writes an atomic terminal manifest and
   completion event before exit.
7. Runtime state lives beneath .orchestrator/outer-loop/: state.json, event inbox/processed,
   registered jobs, open iterations, ledger entries, chain.head, logs, health, alerts,
   ATTENTION.json, and Claude session identity. Runtime content is gitignored except intentional
   schemas and hash checkpoints.

All JSON is canonical UTF-8 with sorted keys and no floats. Writes use same-filesystem temporary
files, fsync, atomic rename, and directory fsync. A controller-wide flock serializes mutation. Events
and iterations are idempotent by UUID.

### 4.3 State machine

| State | Meaning | Machine-checked transitions |
|---|---|---|
| DISABLED | No valid activation grant | valid ENABLE → STARTING; HALT_SET → HALTED |
| STARTING | Verify ledger/policy; reconcile jobs/events/session | eligible work → ITERATING; none → STOPPED_WORK_EXHAUSTED; integrity error → STOPPED_INTEGRITY |
| READY | Agent alive at Stop-hook-confirmed prompt | OPERATOR_INPUT, JOB_COMPLETED, NEXT_STEP_READY → ITERATING |
| ITERATING | One automated turn and one open iteration active | JOB_REGISTERED → WAITING_JOB; USAGE_LIMIT_OBSERVED → WAITING_USAGE_RESET; valid STOP_HOOK → READY/stopped state; no-delta STOP_HOOK → DIAGNOSING; AGENT_EXIT → RECOVERING |
| WAITING_JOB | Open iteration paused on registered work | matching JOB_COMPLETED/JOB_INTERRUPTED → ITERATING; usage limit → WAITING_USAGE_RESET |
| WAITING_USAGE_RESET | Open iteration paused to reset deadline | RESET_DEADLINE_REACHED → ITERATING in the same explicit session |
| DIAGNOSING | Failed iteration and alert recorded | one DIAGNOSE event → ITERATING; identical repeat → STOPPED_REPEATED_FAILURE |
| RECOVERING | Exit/wedge evidence captured | recoverable and within budget → STARTING; repeated failure → stopped state |
| STOPPED_WORK_EXHAUSTED | No eligible work | new scoped operator input/grant → STARTING |
| STOPPED_OPERATOR_BLOCKED | Named human decision/approval required | matching operator/approval event → STARTING |
| STOPPED_BUDGET | Local grant exhausted | new operator grant → STARTING |
| STOPPED_REPEATED_FAILURE | Circuit breaker open | explicit disposition-bearing RESUME only |
| STOPPED_INTEGRITY / STOPPED_UNCLASSIFIED | State, protocol, or validation untrustworthy | explicit repair and RESUME only |
| HALTED | HALT active; agent/jobs stopped | HALT absent plus explicit RESUME and valid grant → STARTING |

READY, WAITING_JOB, and WAITING_USAGE_RESET are idle-but-healthy. READY is not inferred from a prompt
glyph; it requires a matching Stop hook. Waiting states require a registered job or parsed usage
evidence. Work selection and conclusions remain model judgments; event identity, transitions,
budgets, unit liveness, digests, validation, and stops are machine-checked.

### 4.4 Event model

Primary event types are JOB_COMPLETED, USAGE_RESET, and OPERATOR_INPUT. Internal events include
SERVICE_START, JOB_INTERRUPTED, NEXT_STEP_READY, STOP_HOOK, AGENT_EXIT, HEALTH_SAMPLE,
RESET_DEADLINE_REACHED, HALT_SET, and DIAGNOSE.

Each event records schema version, UUID, type, UTC creation time, source, correlation/iteration/job
identity, payload path and SHA-256, required scope, and its own digest. Job output is explicitly
marked untrusted data.

An event file is atomically persisted and fsynced before the client acknowledges it or nudges the
controller socket. Socket loss therefore cannot lose the event. Processed state advances only once a
finalized/open iteration references that event.

When READY, the controller:

1. creates an open iteration;
2. captures the progress-artifact baseline;
3. loads a fixed digest-bound envelope into the isolated tmux buffer;
4. pastes it into the idle Claude PTY and sends Enter.

It never interpolates event text into a shell command. Events arriving during ITERATING remain
queued. A completion matching WAITING_JOB is delivered immediately. Events arriving during usage
wait remain durable until reset.

Operator input normally uses scripts/outer-loop submit. Read-only observation uses the dedicated
tmux socket with attach -r. Writable emergency attachment is an audited override, not routine input.

### 4.5 Runtime and supervision choice

The manager is persistent interactive Claude, never claude -p. First activation assigns an explicit
session UUID; every later launch resumes exactly that session. “Resume most recent” is prohibited.

tmux provides the PTY and observation surface. systemd provides boot start, cgroup ownership, exit
status, logs, resource limits, and filesystem/credential boundaries. The dedicated tmux socket
prevents stopping the outer-loop service from affecting unrelated operator tmux sessions.

The controller distinguishes conditions without spending quota:

- Usage exhausted: a version-pinned ANSI-stripped classifier recognizes a complete known
  exhaustion record and reset instant. It records WAITING_USAGE_RESET before acting.
- Crashed: the Claude/tmux lifecycle ends without planned stop or recognized usage evidence.
- Idle healthy: the PID/session exists and the last matching Stop hook closed the turn, or a
  registered waiting condition exists.
- Busy healthy: an open iteration has advancing pane bytes, CPU time, hook/events, or job progress.
- Wedged: all progress signals remain unchanged for two ten-minute samples while the turn is active
  and not waiting.
- Controller dead: systemd restarts it; heartbeat additionally checks its local lease.

Usage classification must resist output spoofing: known CLI framing, state correlation, and
negative fixtures containing fake limit text in tool/job output are required. Unknown or ambiguous
usage protocol stops fail-closed.

The reset deadline comes from an already-observed message under TZ=UTC and LC_ALL=C. Reboot
reconstructs it from its persisted UTC instant. If no reset time is available, the activation grant’s
conservative provider-window upper bound permits one resume attempt. A second unparseable exhaustion
stops as UNCLASSIFIED_USAGE_PROTOCOL. There is no polling loop.

### 4.6 Detached jobs

The agent requests named job kinds through the controller; arbitrary argv is rejected. The
controller validates the request, records it, rechecks HALT/budget, and starts a separate systemd
unit. That unit is not a descendant of the Claude process and survives the end of a turn.

The job wrapper atomically records:

- job ID and descriptor digest;
- unit identity;
- start/end timestamps;
- exit classification/status;
- response/output, stderr, and raw-stream paths and digests;
- completion-event ID.

It persists the manifest/event before attempting socket notification. On startup, the controller
reconciles every nonterminal job against actual unit state. A unit lost to reboot becomes
JOB_INTERRUPTED, never silent success or eternal waiting.

### 4.7 Iteration ledger

An iteration begins before prompt delivery. Waiting for a long consultation does not end it and has
no minute-scale timeout. CLI exit or reboot leaves the open record durable. Terminal success or
failure produces one immutable canonical entry linked to the previous SHA-256.

Schema:

    {
      "schema_version": 1,
      "loop_id": "activation UUID",
      "sequence": 17,
      "iteration_id": "UUID",
      "previous_entry_sha256": "hex or null",
      "started_at": "RFC3339 UTC",
      "ended_at": "RFC3339 UTC",
      "trigger_events": [
        {"event_id": "UUID", "type": "JOB_COMPLETED", "sha256": "hex"}
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
          "kind": "BROKER_OPERATION or DETACHED_JOB",
          "started_at": "UTC",
          "ended_at": "UTC or null",
          "job_id": "UUID or null",
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
          "identity": "PLAN-006/revision-2",
          "path_or_uri": ".orchestrator/plans/PLAN-006.md",
          "before_sha256": "hex or null",
          "after_sha256": "hex",
          "validator": "plan-v1",
          "validation_receipt_sha256": "hex"
        }
      ],
      "failure": {
        "class": "NO_DURABLE_DELTA or null",
        "fingerprint": "hex or null",
        "diagnosis": "mechanical and agent diagnosis",
        "evidence_refs": ["path"]
      },
      "resources": {
        "claude_session_id": "UUID",
        "agent_restarts": 0,
        "completed_iterations_in_grant": 3,
        "codex_consults_in_grant": 1,
        "worker_dispatches_in_grant": 0
      },
      "next_step": {
        "disposition": "READY, WAIT_JOB, WAIT_RESET, WORK_EXHAUSTED, OPERATOR_BLOCKED, or BUDGET_EXHAUSTED",
        "summary": "concrete next action",
        "required_event_or_artifact": "typed condition or null"
      },
      "entry_sha256": "SHA-256 with this field omitted"
    }

Failure fingerprints hash the class, normalized subsystem/operation, stable exit or validator code,
and evidence signature. Timestamps and free-form prose are excluded so rewording cannot evade the
breaker.

The installed controller—not Claude—writes entries. The agent’s mount makes ledger/state read-only.
A verification command recomputes every digest and sequence. Corruption stops the loop. Clean stops
or daily checkpoints persist chain.head into the tracked evidence area, but checkpoints never count
as iteration progress.

### 4.8 Progress validator

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

1. PLAN_REVISION: template-valid plan, expected ID, incremented revision, consistent frontmatter, and
   a semantic change outside generated provenance/checkpoint fields.
2. VERDICT: schema-valid digest-bound PASS/BLOCK or review verdict with reviewer/model identity,
   reviewed digest, reasons, and evidence.
3. DECISION_RECORD: new/revised decision with trigger, authority, inputs, decision, and evidence
   digests.
4. PR: broker receipt confirmed against the remote API, targeting integration, with immutable PR
   number/URL, head SHA, base SHA, and reviewed attempt identity.
5. REQUEST_LEDGER_TRANSITION: parsed row whose status or completion evidence validly changed and
   references a real artifact.
6. SPEC_OR_ATTEMPT_RECORD: schema-valid spec, finalized attempt manifest, escalation, or integration
   record produced by the installed dispatcher with normal bindings.

Unknown types do not count. Deletion does not count without an allowlisted tombstone decision.
Test output, raw logs, pane transcripts, state/events, job records, health samples, alerts,
PENDING/NEXT, and outer-loop ledger/checkpoints never count. A digest-only or timestamp-only rewrite
does not count.

If Stop arrives while a registered job remains live, the iteration enters WAITING_JOB instead of
being validated. Otherwise, zero valid deltas produces FAILED/NO_DURABLE_DELTA, ATTENTION.json, and
DIAGNOSING. The diagnosis event includes the baseline, changed noncounting files, expected artifact
types, and hook/pane evidence. A repeated identical fingerprint opens the breaker.

Validator exception, writable-validator detection, or validator/schema digest mismatch is
VALIDATOR_COMPROMISED and stops immediately.

### 4.9 Stopping and circuit breakers

The agent submits exactly one typed next-step disposition at Stop. The controller validates it:

- WAIT_JOB requires a live registered job.
- WAIT_RESET requires recognized limit evidence and a deadline.
- READY requires eligible in-scope work.
- OPERATOR_BLOCKED must name the exact decision, approval, credential, or external action.
- WORK_EXHAUSTED requires no eligible ledger request or pending event.
- BUDGET_EXHAUSTED follows the activation grant, not provider usage exhaustion.

Breakers:

- two consecutive finalized failures with the same fingerprint;
- three unplanned agent exits in sixty minutes;
- two confirmed wedges of the same open iteration;
- invalid ledger chain;
- installed policy/validator digest mismatch;
- ambiguous usage protocol;
- invalid event schema;
- broker invariant failure;
- HALT.

A stop atomically records state, writes timestamped alert evidence and
.orchestrator/outer-loop/ATTENTION.json, warns in the systemd journal, stops the agent, and leaves the
quota-free controller listening. ATTENTION includes reason, evidence paths/digests, current
request/iteration/session, exact resume precondition, and whether jobs were stopped.

Stopped states never spin. Resume requires the qualifying event or explicit disposition-bearing
operator command.

### 4.10 Safety and revocation

The persistent --dangerously-skip-permissions process is a standing code-execution capability and
must not inherit the operator’s ambient account.

The agent service uses:

- private HOME, tmp, and dedicated tmux socket;
- NoNewPrivileges;
- empty capability bounding/ambient sets;
- private devices;
- strict system/kernel/cgroup protection;
- resource ceilings;
- restricted address families;
- explicit read/write mounts.

It hides:

- the operator’s .ssh and GitHub configuration;
- GH_TOKEN, GITHUB_TOKEN, and SSH_AUTH_SOCK;
- Codex configuration/token;
- the user-systemd bus;
- installed controller, validator, and ledger;
- unrelated home, /root, and /srv paths;
- sudo capability.

The minimum Claude credential/config is bound read-only; mutable Claude cache/session data uses the
private HOME. The agent can read and potentially exfiltrate its own Claude credential and exposed
repository content, modify writable checkout files, and consume network/quota. That unavoidable
residual is explicit. It cannot, by design and negative test, access GitHub/SSH/Codex credentials,
the user bus, installed safety plane, remote main, or unrelated filesystem paths.

Credentialed operations use a typed controller broker, never arbitrary shell. The broker:

- rechecks HALT, grant, scope, and budget;
- invokes the installed parent dispatcher;
- records inputs and result digests;
- rejects source/target main;
- rejects autonomous trust-critical merge;
- rejects absent/invalid high-risk approval;
- treats unclassified paths as high risk.

scripts/outer-loop halt is the instant revocation command. It creates HALT first, stops the agent and
registered job units, verifies inactive cgroups, and records HALTED. Manual fallback is:

    touch /home/val/orchestrator/.orchestrator/HALT
    systemctl --user stop orchestrator-outer-agent.service

Removing HALT does not resume. Suspected compromise additionally requires Claude credential
revocation/rotation.

### 4.11 Codex route around bwrap

The loop does not wait for a host sandbox fix and does not change the AppArmor sysctl.

For a CODEX_CONSULT job, the controller:

1. resolves every context file outside the model job;
2. bounds size, strips secrets, concatenates complete context with path/digest headers, and hashes
   stdin;
3. starts an independent hardened systemd job with disposable HOME/workdir, only its Codex
   credential/config, and no repository/operator-home mount;
4. invokes the proven stdin/no-repository-read command form with gpt-5.6-sol, high reasoning, and
   service_tier=priority;
5. applies no minute-scale timeout;
6. records response, raw JSON stream, stderr, exit metadata, and SHA-256 receipts;
7. emits JOB_COMPLETED.

Implementation must recover and fixture the working PLAN-005 attempt-3 argv. If it cannot be
reproduced inside the external systemd boundary, activation blocks. Fixing AppArmor remains a
separate high-assurance decision.

### 4.12 Alternatives considered

**A. Periodic claude -p --continue with babysitting.**  
Still turn-scoped. It must keep a paid turn alive for hours or rely on another clock. It preserves
the fatal lifetime mismatch, adds orientation cost, and cannot represent durable idle health.
Rejected.

**B. tmux-resident Claude with a shell watchdog.**  
Fixes PTY liveness, but tmux is not an event broker, validator, ledger, capability boundary, or boot
reconciler. Pane/process checks alone can still waste windows silently. The selected design retains
tmux but assigns supervision and policy to systemd/controller. Rejected as the final design.

**C. Event-triggered one-shot claude -p --resume.**  
Better than the timer, but a turn still cannot receive the completion of work it launches, event
startup repeatedly rehydrates context, and exact background behavior remains fragile. Rejected for
revision 1.

**D. Cloud schedules/routines.**  
Cannot operate the on-box systemd/isolation/trust-critical lane without a new remote control surface.
May complement CLOUD-SAFE work later, but cannot satisfy R23. Rejected.

The hybrid wins because it separates deterministic liveness, validation, state, and safety from
model reasoning while preserving a genuinely live interactive runtime.

## 5. Affected boundaries & consumers

1. CLAUDE.md autonomy, HALT, bootstrap, trust closure, review independence, approval, quota, merge,
   and main-promotion rules.
2. REQUEST-LEDGER, plans, specs, verdicts, decisions, approvals, attempts, escalations, and their
   schemas.
3. scripts/dispatch.py and installed dispatcher commands for reconcile, launch, health, cancel, push,
   PR, merge, and integration.
4. systemd user manager, linger, cgroups, tmux, journal, filesystem atomicity, clocks, and reboot.
5. Claude version/session/hooks/usage output and Codex stdin/JSON-stream protocols.
6. Claude, Codex, GitHub, SSH, and systemd credentials and network boundaries.
7. Integration target, protected main, PR bindings, candidate versus installed control-plane code.
8. Event, job, health, ledger, alert, checkpoint, and retained attempt evidence.
9. Repository tests/CI and host-only lifecycle/security drills.
10. Operator submit/status/read-only attach/halt/resume/install workflows.

The transitive trust closure includes every parser, schema, library, config, entrypoint, classifier,
hook, unit template, installer, broker, validator, and state transition affecting these behaviors.
Unknown dependencies fail high-risk.

## 6. Ordered implementation steps

1. Verify R23 evidence, absence of deleted units, CLI versions/help, PLAN-005 attempt-3 command,
   systemd/linger/tmux, HALT, autonomy, branch protection, and credential paths. Replace section 2
   citations with path:line or evidence digest.
2. Add event, state, grant, job, open-iteration, finalized-ledger, artifact-receipt, alert, and
   capability schemas plus disabled tracked policy and canonical fixtures.
3. Implement atomic state, locking, durable events, replay, transitions, injectable clock, ledger
   verification, budgets, alerts, status, halt/resume, and startup reconciliation.
4. Implement the closed artifact-validator registry and baseline/receipt logic using installed-parent
   schema parsers.
5. Implement named detached jobs, independent units, atomic terminal manifests, completion events,
   exactly-once reconciliation, and reboot interruption.
6. Implement explicit Claude session identity/resume, dedicated tmux socket, pipe-pane logging,
   safe buffer delivery, Stop hook, and usage/health classification.
7. Add controller, agent, heartbeat, and job unit templates plus installer/uninstaller. Units point
   at the authorized installed snapshot, not mutable repository code.
8. Implement filesystem/credential isolation and the typed capability broker. Add negative security
   tests before any live model start.
9. Implement Codex consultation using recovered attempt-3 stdin invocation and external systemd
   isolation. Do not change AppArmor.
10. Add deterministic tests for schemas, state, chain corruption, replay, usage parsing/spoofing,
    reset/reboot, detached completion, no-delta validation, breakers, HALT races, wedge detection,
    CLI drift, capability denial, and candidate self-activation.
11. Update AGENTS.md, CLAUDE.md, and operator runbook with runtime, supported input, state/alerts,
    budgets, revocation, residual risk, CLI upgrade, Codex workaround, evidence, and recovery.
12. Run ./scripts/test, actual-unit security tests, CLI/hook/session smoke tests, and detached-job
    canary. Produce bound evidence. Do not activate.
13. Submit the same revision for fresh SOL Critical review and Claude challenge. Resolve findings in
    a new revision until both PASS, then obtain operator authorization.
14. Install with the agent disabled. Confirm Linger=yes, start only the deterministic controller,
    test HALT/status/spool, then enable a tightly scoped grant and run live drills.
15. Enable normal scoped operation only after the natural usage-reset and operator-approved reboot
    drills pass. Reconcile R23 and record completion conformance.

## 7. Failure modes & blast radius

| Trigger | Consequence | Mitigation |
|---|---|---|
| Controller crash | Events temporarily undelivered | systemd restart, durable replay, lease heartbeat, crash breaker |
| Claude exit | Runtime disappears | classify evidence before exact-session resume |
| Usage wording changes | Wrong reset/crash classification | version-pinned parser, spoof tests, unknown-protocol stop |
| Reboot during reset | Work remains paused | persisted UTC deadline and boot reconciliation |
| Job finishes while controller down | Socket notification lost | manifest/event persisted first, startup replay |
| Job killed by reboot | Eternal wait | JOB_INTERRUPTED event; fresh named retry only |
| Stop hook absent | Validator bypass risk | protocol/integrity stop; no success without hook receipt |
| No artifact | Silent wasted iteration | NO_DURABLE_DELTA alert and repeated-failure breaker |
| Cosmetic/log change | False progress | closed semantic validators; loop artifacts excluded |
| False WAIT state | Infinite idle | live job or recognized usage evidence required |
| Long silent valid work | False kill | two samples; any CPU/output/job progress prevents kill |
| True wedge | Window stalls | cgroup recovery once; second wedge stops |
| Torn ledger write | Lost/corrupt memory | fsync/rename/hash chain; fail closed |
| Candidate alters validator | Self-approval | active installed snapshot is read-only |
| Agent exfiltrates secrets | Credential compromise | expose only Claude credential; halt and rotate |
| Agent damages checkout | Local corruption | disposable/scoped work area, broker/gates/review, reinstall safe plane |
| Broker permits main/high-risk merge | Trust-boundary breach | installed-parent deny, negative tests, branch ruleset |
| HALT race | Side effect after stop | HALT-first plus pre-side-effect recheck and cgroup stop |
| Heartbeat misfires | Unneeded model start | heartbeat cannot invoke model for status |
| Grant too broad | Excess work/quota | explicit scope, ceilings, expiry, approval |
| tmux dies | Session loss | systemd report and exact-session/ledger recovery |
| bwrap remains broken | Consult failure | stdin context and external systemd isolation |
| Hardening unsupported | Excess host access | activation-blocking verify and negative probes |

Worst credible case is arbitrary command execution within the Claude unit’s exposed filesystem and
network, exfiltration of its Claude credential/repository content, and local checkout damage. The
design keeps GitHub/SSH/Codex/systemd credentials and the installed safety plane outside that unit,
but does not claim --dangerously-skip-permissions is harmless.

Recovery is HALT, stop all units, revoke Claude credentials, preserve evidence, audit remotes,
recreate the control checkout, reinstall the last authorized snapshot, and remain disabled pending
a new Critical authorization.

Irreversible effects are model quota/cost and data already transmitted to provider APIs.

## 8. Validation plan (falsifiable)

Deterministic tests use fake Claude/Codex binaries, injectable time, disposable state, and
systemd/tmux adapters. Host-bound tests repeat lifecycle and security checks with real units.

1. **Usage exhaustion:** fake Claude starts as S1, opens an iteration, emits a captured limit record,
   and exits or waits. Before reset, assert zero model calls. At reset, assert immediate exact resume
   of S1 and the same iteration, with no crash/failure count. Restart controller during the wait.
   The old fixture fails because claude -p exits and continuation depends on a later timer. A natural
   live limit/reset is required before completion.
2. **Detached completion while idle:** launch a fake independent job, let Claude enter WAITING_JOB,
   then complete it. Assert manifest-before-event, delivery within five seconds, exact-session receipt,
   and one successful iteration. Repeat with controller down. The old fixture fails because no live
   process receives completion.
3. **Reboot:** persist an open iteration, queued event, S1, and waiting state; kill all processes;
   restart the service harness. Assert chain verification, reconciliation, exactly-once delivery, and
   S1 continuation. Then perform an operator-approved actual VPS reboot with Linger=yes. The old
   fixture has no explicit session/open-iteration recovery.
4. **Wedge:** fake an active process with no output, CPU, hooks, or jobs. First sample does not kill;
   second stops the cgroup and resumes once. A second wedge opens the breaker. CPU/output/job-progress
   controls must survive. The old fixture has no confirmed-hang logic.
5. **No delta:** deliver an event and Stop while only logs/state/timestamps change. Assert
   FAILED/NO_DURABLE_DELTA, alert, diagnosis, and no success. Repeat identically and assert no third
   prompt. The old fixture accepts exit zero.
6. **Ledger durability:** kill between each atomic-write phase; recovery yields the old or new
   complete state. Modify/delete/reorder entries and assert STOPPED_INTEGRITY before Claude starts.
7. **Event integrity:** duplicate/reorder events, lose socket notifications, and include shell
   metacharacters/fake limit text. Assert exactly-once handling, safe tmux delivery, and no spoofed
   usage transition.
8. **HALT and broker:** race HALT against prompt, job, PR, and merge. Assert no action after the final
   HALT check. Requests for main, arbitrary argv, unapproved high-risk work, trust-critical merge,
   candidate validator, or expired grant must be denied.
9. **Credential isolation:** from the real agent unit, attempt reads of SSH/GitHub/Codex credentials,
   user bus, installed validator/ledger, /root, and unrelated home/srv, and writes outside the
   allowlist. All fail.
10. **CLI compatibility:** record claude --version; prove Stop-hook receipt, explicit S1 creation and
    exact resume, and real limit-fixture parsing. Reproduce the PLAN-005 attempt-3 Codex stdin
    invocation in the hardened consult unit.
11. **Stops/budgets:** exercise exhausted work, operator block, each local ceiling, expiry, repeated
    failures, crash loop, and wedge loop. Assert one alert, no spinning, and only a qualifying resume.
12. **Suite/evidence:** ./scripts/test passes; CI remains exactly ci; snapshot, policy, units, test
    logs, live receipts, and final ledger head are digest-bound in completion evidence.

The five headline tests explicitly run against both the deleted-design fixture and the replacement;
each must fail old/pass new.

## 9. Rollback / irreversibility

1. Run scripts/outer-loop halt and verify all agent/job cgroups inactive.
2. Disable controller, agent, and heartbeat units; remove wants links; daemon-reload. Do not restore
   the old timer.
3. Remove/repoint the installed snapshot and restore the installer’s hook-config backup.
4. Disable/remove the local activation grant. Preserve ledger, events, jobs, logs, and alerts.
5. Rotate Claude credentials if exposure is suspected and audit GitHub/SSH/Codex access.
6. Resume manually in an operator-controlled session.

Git, unit, tmux, linger, PR, and local-state changes are reversible. Model quota and provider-bound
content are not. No kernel/AppArmor change is included.

## 10. Open questions / operator decisions

None for the design.

The operator must still execute existing authority steps: authorize the final Critical digest,
provide scoped local budgets, enable linger if absent, approve the live reboot drill, and explicitly
enable production operation. These are fail-closed execution approvals, not unresolved design
choices.

## 11. Provenance (filled during challenge/authorization — NOT by the drafter)

- **Challenge (Claude):** PENDING — must be filled by Claude.
- **Disposition (drafter):** PENDING challenge.
- **Dual-validation (high-assurance/control-plane):** SOL verdict PENDING; Claude verdict PENDING.
- **Authorization:** PENDING; no unit may be installed or enabled.
- **Completion reconciliation:** N/A — draft only; implementation has not begun.
```
