# Claude disposition — SOL review of PLAN-005 draft (BLOCK, 7 blocking + 2 conditions + counterargument)

**Decision: ACCEPT finding 10 (the strongest counterargument) as the governing design choice.**
The plan is REDESIGNED around the minimal fail-closed rule instead of a hardened same-user
fallback. This moots findings 1, 2, 4, 5, 6 (they attack the fallback we are no longer building)
while their substance is recorded as the requirements any FUTURE hardened fallback must meet.

Redesigned scope:
1. **Fail-closed refusal (the core):** when D5 isolation is unavailable, dispatch REFUSES before
   `claim_slot`, before attempt-directory creation, before any worker/TEST/regression execution.
   One immutable execution-mode decision at preflight, consumed by EVERY decision point (finding 3
   fully sustained: worktree_root :540, launch :717, fallback worker :860, fallback TEST :946,
   run_regression_gate :623) — no recalculation, no downgrade on retry/remediation.
2. **Break-glass is exposure, not protection:** ORCH_ALLOW_UNISOLATED=1 documented as explicit
   acceptance of FULL operator-credential and host-state exposure; requires a separate human
   authorization artifact per use; never described as a protected mode. No credential-registry
   heuristic, no unshare probe ladder, no netns launcher — deleted from scope.
3. **Non-vacuous validation (findings 7+8 sustained, applied to the smaller surface):** every
   refusal test carries a positive control (same fixture launches when isolation IS available /
   break-glass IS authorized); two mandatory validation environments (userns-restricted → refusal
   proven; D5-available → the real isolated path exercised); refusal-only local runs reported as
   incomplete security validation, never as full pass.
4. **Fold in the non-vacuous worker_isolation.sh drills (finding 9 condition accepted):** dynamic
   operator-home resolution, planted positive disk canary readable by operator and provably
   unreadable by the isolated worker, fail if the canary/probe never ran, reliable cleanup.
5. **Residual record:** the deferred hardened fallback, if ever built, must provide filesystem,
   pathname-socket/IPC, /proc, descendant-lifecycle (PID ns + tree kill), and network containment
   with the non-vacuous validation above (findings 1/2/4/6 preserved as its entry bar).
