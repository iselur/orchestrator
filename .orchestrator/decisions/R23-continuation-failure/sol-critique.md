This revision is blocked by four safety-material gaps. The core architecture is executable, and several recovery paths are well designed, but the plan can still go indefinitely quiet and its authority/budget files are not protected strongly enough from the persistent agent.

### 1. Liveness trace

| Stop-producing-work path | Detection/recovery | Assessment |
|---|---|---|
| Recognized usage exhaustion | Durable deadline, exact-session resume, reboot reconstruction | Covered |
| Classifier drift or unexplained agent exit | Raw evidence, immediate alert, up to three budgeted probes, terminal stop | Covered |
| Active Claude wedge | Two ten-minute samples, evidence capture, bounded recovery | Covered |
| Agent/tmux exit | Unit lifecycle evidence and controller reconciliation | Covered |
| Reboot | Linger precondition, durable session/iteration state, unit reconciliation | Covered, subject to the required real drill |
| Job completes while controller is down | Manifest/event persisted before notification and replayed | Covered |
| Job lost during reboot | Reclassified `JOB_INTERRUPTED` | Covered |
| **Registered job remains alive but wedged** | None | **BLOCKER** |
| **Controller hangs or exits successfully** | Detection is mentioned, but recovery is not specified | **BLOCKER** |

#### B1 — A live-but-wedged detached job can recreate the original silent failure

`WAITING_JOB` remains healthy merely because a registered unit is live. Requirement 12 prohibits liveness probes while that condition remains valid, and the wedge definition in requirements 23–24 applies to an active, nonwaiting Claude turn—not to a detached job.

There is no job equivalent of:

- consecutive no-output/no-CPU/no-stream-progress samples;
- an overdue-job alert;
- a terminal `STOPPED_JOB_WEDGE`;
- a bounded recovery or interruption policy.

The expiry policy does not close this path: “cancellation at the next safe checkpoint” may never occur for a hung process. This is especially material because `codex-consult` intentionally has no minute-scale timeout. A live but deadlocked Codex unit can therefore leave the loop in `WAITING_JOB` indefinitely, exactly resembling the nine-hour orphaned consultation failure.

This needs a conservative detached-job liveness protocol. It need not impose a minute-scale SOL timeout, but it must eventually alert and enter a bounded recovery/stop state when the unit, JSON stream, CPU time, and output all cease advancing.

#### B2 — Controller liveness detection does not guarantee controller recovery

The controller unit uses `Restart=on-failure`. That does not restart an unexpected clean exit. A hung controller also remains “active” to systemd.

The heartbeat is required to “detect” a dead controller lease, but the plan does not specify that the independent heartbeat must:

1. persist an alert without relying on the controller;
2. terminate a stale controller cgroup if appropriate;
3. restart or explicitly start the controller;
4. verify lease advancement after restart; and
5. enter a durable loud-stop state after bounded unsuccessful recoveries.

A detection-only heartbeat leaves the operator responsible for restarting the very mechanism intended never to require manual continuation. A hung controller holding the global flock may also prevent the heartbeat from recording state through normal mutation paths.

### 2. Budget accounting

The reservation mechanics themselves are credible: pre-action reservation, serialized durable state, UUID idempotency, conservative consumption, reboot persistence, and ceiling checks can all be implemented without a vendor API.

But the two meters do not bound autonomous spend as written.

#### B3 — One admitted iteration can initiate unmetered model work and broker actions

The plan meters:

- iteration openings; and
- named detached-job launches.

It does not establish that every model-bearing action is one of those admissions. In particular:

- `worker_dispatch_low_risk` is described as a broker capability, but the plan never says each dispatch must reserve a detached-job unit.
- The action ledger distinguishes `BROKER_OPERATION` from `DETACHED_JOB`, so an iteration can apparently request multiple worker dispatches or other costly broker operations without another reservation.
- The Claude unit contains a usable Claude credential, network access, the Claude executable, and arbitrary shell execution. No control prevents the admitted agent from launching another Claude process or otherwise using its own credential.
- A single busy iteration is allowed to run indefinitely while pane or CPU activity advances. Thus the iteration ceiling is not a ceiling on model calls, elapsed execution, or provider spend.
- Exact-session resumptions of an already-open iteration are not separately metered, so ambiguous prompt delivery or repeated resumptions need an explicit idempotency/recovery bound.

Requirement 29 states that only authorized turns/jobs may invoke a model, but the isolation design does not enforce that statement.

Every worker dispatch and model invocation must be mapped to a named, reserved admission. Direct recursive Claude invocation from the agent namespace must be prevented or separately metered. A grant-expiry or generous non-minute-scale runtime boundary must also terminate an admitted invocation eventually; otherwise one unit is not a bounded spend unit.

### 3. Value-floor evasion

The value floor is mechanically computable but readily evaded:

- Add any counting `VERDICT`, `DECISION_RECORD`, or other artifact to each plan-revision iteration.
- Alternate plan IDs.
- Insert a failed/no-delta iteration after every two revisions. Because “any nonqualifying finalized iteration resets the streak,” an intentional failure resets it.
- Insert another nonqualifying recovery iteration between revisions.

This contradicts the broader claim that it stops plan accretion, but the independent iteration ceiling still bounds the resulting activity. Under the authorized stop-rule, this is advisory rather than independently blocking.

A stronger rule would maintain a per-plan streak until a shipment-class result occurs and would not let failures, liveness probes, or cheap auxiliary records reset it.

### 4. Progress validation

The validator is non-vacuous against logs, timestamps, ledger entries, and formatting-only changes. It does require a durable semantic file change and a typed receipt.

It does not establish useful progress, however. The agent can fabricate counting deltas such as:

- a schema-valid but low-value decision record;
- a verdict carrying only asserted reviewer/model identity;
- a semantically changed but inconsequential plan paragraph;
- a request-ledger transition referencing another self-created artifact;
- a schema-valid spec that does not advance execution.

This is partly acknowledged by the non-goal saying the ledger does not prove correctness, so it is advisory under the stop-rule. Nevertheless, `VERDICT` should require independently authenticated execution provenance, and only artifacts representing an externally meaningful state transition should reset the value floor.

### 5. HALT, grants, approvals, and authority

Remote `main` and trust-critical merge are adequately denied in the stated design: the agent lacks GitHub/SSH credentials, the installed broker rejects `main`, and both autonomy modes exclude high-risk autonomous dispatch.

#### B4 — The agent can potentially rewrite the authority and revocation artifacts

The agent is explicitly allowed to modify writable checkout files. Meanwhile:

- HALT is `/home/val/orchestrator/.orchestrator/HALT`, inside that checkout.
- The activation grant is described only as a gitignored local JSON file.
- The grant’s `operator_identity` is merely a string; no signature, protected origin, or immutable operator receipt is defined.
- The list of paths hidden from the Claude unit names controller, validator, ledger, and budget state, but not HALT, the activation grant, or approval artifacts.
- Existing approval artifacts also appear to reside beneath the writable repository tree.

Because the agent service runs under the operator’s UID, ordinary Unix ownership or mode checks would not authenticate these files. As written, the agent could potentially:

- remove HALT before a broker’s recheck observes it;
- install a new grant UUID and replenish both counters;
- widen scope, mode, expiry, or capabilities;
- create something syntactically resembling an approval artifact.

This directly crosses the stop-rule’s “mint its own approval,” “exceed its grant,” and “ignore HALT” boundaries.

HALT, grants, approval artifacts, and their parent namespaces must be inaccessible for mutation from the agent mount namespace and authenticated as operator-originated. The controller must fail closed on replacement or provenance failure. The emergency HALT path must also stop all registered job units even when the controller is hung or dead; the shown manual fallback currently stops only the agent service.

### 6. End-to-end executability

No inherent Ubuntu 24.04/systemd-user/tmux impossibility is evident. Dedicated tmux sockets, explicit session resume, Stop hooks, transient job units, durable spool files, user-manager linger, and externally isolated stdin-based Codex consultations are all plausible.

The plan correctly makes actual Claude session/hook support, systemd hardening directives, linger, and the recovered Codex stdin invocation activation preconditions. Failure of one of those smoke tests should block activation, as specified.

The blockers above are design completeness failures rather than unavailable host features: the box can implement the required protections and watchdogs, but revision 2 does not yet require them.

VERDICT: BLOCK
