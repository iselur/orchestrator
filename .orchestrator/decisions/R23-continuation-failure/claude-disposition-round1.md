# Claude disposition — adversarial review of PLAN-006 rev2 (BLOCK, 4 safety-material)

All four SUSTAINED. They are exactly the class of defect this loop exists to prevent — B1 IS the
nine-hour orphan in new clothes, and B3 means the budget bounds turns, not spend.

**B1 — live-but-wedged detached job leaves the loop in WAITING_JOB forever. SUSTAIN.**
Add a detached-job liveness protocol symmetric with the Claude-turn wedge rule: sample unit state,
CPU time, output/JSONL stream growth, and file mtimes; if ALL are unchanged across two consecutive
samples at a conservative interval (default 15 min; job-kind-configurable), raise JOB_OVERDUE →
alert + ATTENTION.json; after a bounded number of consecutive stalled windows (default 4 ≈ 1h),
enter STOPPED_JOB_WEDGE with the evidence captured and the unit terminated. This does NOT impose a
minute-scale SOL timeout (a long consult with advancing CPU/stream survives indefinitely, per the
standing policy) — it only catches a job whose EVERY progress signal is flat.

**B2 — detection-only heartbeat. SUSTAIN.** The independent heartbeat must (1) persist its alert
without the controller, (2) kill a stale controller cgroup, (3) start/restart the controller,
(4) verify lease advancement after restart, (5) after N failed recoveries enter a durable loud-stop.
Controller unit uses Restart=always (not on-failure) so a clean unexpected exit also restarts. The
heartbeat must not require the controller's flock to record state (separate path).

**B3 — the iteration meter is not a spend ceiling. SUSTAIN — this is the operator-facing one.**
Required: EVERY model-bearing action must map to a named RESERVED admission. Specifically:
(a) each worker dispatch reserves a detached-job unit (BROKER_OPERATION may not launch models
outside a reservation); (b) recursive Claude invocation from the agent namespace is PREVENTED
(no `claude` on the agent unit's PATH except the controller-owned session; enforce via unit
environment/exec restrictions) or, if that proves impossible, separately metered and alerted;
(c) an admitted iteration has a generous but finite wall-clock ceiling (default 4h, non-minute-scale
per policy) after which it is terminated and recorded — one unit must be a bounded spend unit;
(d) exact-session resumptions of an already-open iteration are metered with explicit idempotency
bounds. Add a third meter if simpler: MODEL_INVOCATIONS per grant window, incremented by the
controller at every admission.

**B4 — value-floor evasion. SUSTAIN.** The floor must not reset on self-produced companion
artifacts. Only artifacts representing an EXTERNALLY MEANINGFUL state transition reset it: a merged
PR, a dispatched attempt reaching a terminal gate outcome, a ledger row reaching done/blocked, or an
operator-visible deliverable. A VERDICT or DECISION_RECORD produced by the loop about its own plan
does NOT reset the floor (that is the evasion). Plan revisions on the same plan id count toward the
floor regardless of what else the iteration also emitted.
