# Claude disposition — SOL critique round 2 of PLAN-003 rev3 (VERDICT: BLOCK, 4 findings)

Converging: rev2's 12 blockers reduced to 4 new, narrower ones; assertion sets, tree revalidation,
and the 6-dispatch sequence were explicitly assessed non-blocking. All 4 SUSTAINED with chosen
mechanisms:

| Finding | Disposition | Chosen mechanism for rev4 |
|---|---|---|
| 1. Old dispatcher = parallel authorization path | SUSTAIN | Dispatch 0 installs a machine-enforced choke point: authoritative attempt-evidence roots and the PR/push credential become accessible ONLY through the root-owned bootstrapctl launcher path; a direct `scripts/dispatch` invocation pre-Dispatch-4 fails closed at preflight (no credential, no writable evidence root, no manifest) and provably cannot create authoritative evidence or open a PR. Add the direct-bypass test with evidence + PR spies at zero. |
| 2. Approval-schema prerequisite self-gated/circular | SUSTAIN | Adopt SOL's alternative: embed the MINIMAL strict approval parser + schema needed by Dispatch 0 inside the operator-installed, independently-reviewed bootstrap artifact itself (frozen, digest-bound, outside candidate content). The separate approval-schema plan then upgrades the full system later WITHOUT being on PLAN-003's critical path — removes the circular dependency and un-blocks sequencing. Dispatch 0 refuses unless the embedded schema digest validates. |
| 3. Activation manifests ≠ state machine | SUSTAIN | (a) Genesis variant `previous_active_commit: null` bound to an approval-authorized anchor + Dispatch 0 digest; (b) root-owned singleton active-head: append-only activation ledger + atomic compare-and-swap head file; (c) every dispatcher verifies BOTH its historical manifest AND that its commit == selected head; (d) activation/rollback are atomic head transitions; (e) genesis, sibling-race, stale-parent-after-successor, rollback, crash-interruption tests. |
| 4. Producer auth vs same-UID process manipulation | SUSTAIN | The event-producing controller runs OUTSIDE the candidate UID (controller = dispatcher/operator side; candidates = codex-worker — matching the existing D5 split); if that separation cannot be established at launch, testing aborts fail-closed. Negative tests: ptrace attach, process_vm_readv/writev, pidfd_getfd from candidate → controller must all fail. |

Non-blocking assessments accepted as-is (no plan change): semantic sufficiency limitation
(assumption 8), tree-revalidation residual window (recorded residual), Dispatch 3 transitional
state, §8 breadth. Rev4 adds ONLY the four amendments + their tests; everything else is frozen to
avoid churn-induced regressions.
