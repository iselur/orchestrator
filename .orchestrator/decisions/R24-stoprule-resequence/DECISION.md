# DECISION — planning stop-rule + resequencing + Phase-1 trimmed kernel

**Authority:** operator, 2026-07-14 ("Approve both"), in response to Claude's proposal.
**Tier:** control-plane (governs when plans are authorized and what order work ships).

## 1. Planning stop-rule (BINDING, effective immediately)

A plan is AUTHORIZED when an adversarial review round returns **zero findings that are either
(a) security-material or (b) executability-blocking**. Advisory notes, hardening suggestions, and
re-litigation of explicitly recorded residuals do NOT block authorization.

Rationale: an adversarial reviewer asked to find problems will always find problems. The planning
loop previously had NO stopping condition — the same defect diagnosed in the deleted continuation
timer (`R23-continuation-failure/REFRAME-outer-loop.md`) and the exact risk named as #1 by the
vision gap review ("recursive control-plane accretion becoming the product").

Escalation: if Claude and the reviewer disagree on whether a finding is material, it goes to the
operator — never silently resolved, never silently iterated.

## 2. Resequencing (BINDING)

Implementation order — the outer loop OVERTAKES the measurement layer:

1. **PLAN-005** — fail-closed isolation refusal (small, self-contained, closes a live hole).
2. **PLAN-006** — the OUTER LOOP (autonomous continuation). This is what stops the operator having
   to restart the session every ~5h; a factory that cannot survive the night is worth less than a
   factory with better dashboards.
3. **PLAN-003** — Phase 1 verdict integrity, TRIMMED KERNEL scope (see 3).
4. **PLAN-004** — Phase 2 measurement layer.

## 3. Phase-1 scope: TRIMMED TRUTHFUL KERNEL (BINDING)

Phase 1 ships the smallest mechanism that makes the gate stop certifying unrun/vacuous/forged tests:

**IN (the kernel):**
- Machine-enforced TEST ATTESTATION: parent-owned required-test IDs + exact expected-assertion sets;
  SKIP / missing / zero-assertion / forged ⇒ `failed_test` BEFORE the reviewer runs.
- Producer-authenticated assertion events (controller outside the candidate UID; env scrub + FD
  close before candidate exec) — without this, attestation is forgeable and the kernel is theatre.
- Parent-content (blob-verified) required tests — candidate-modified copies are supplemental only.
- Verdict schema v4: exact one-criterion-per-acceptance-criterion count/order/text binding; strict
  JSON parse (duplicate-key rejection); launch-time persisted criteria vector.
- Structured `advisory|blocker` findings + mechanical blocker predicate in `evaluate_binary_review`.
- Credential/evidence CHOKE POINT: authoritative evidence roots + PR/push credential reachable only
  via the root-owned launcher; direct dispatcher runs cannot produce authoritative artifacts.
- Metrics extraction (`scripts/metrics_report.py`) + corrected semantics (Phase 2's precondition).
- Reviewer receives the machine attestation summary (log tail secondary).

**DEFERRED (recorded, not cancelled — each becomes its own later spec):**
- Full activation state machine (append-only activation ledger + CAS singleton head + crash oracles).
- The frozen bootstrap verifier's full profile system (Dispatch 0 as designed) — replaced in the
  kernel by: the choke point + operator-run installation with recorded digests.
- Shared content-addressed gate venv hardening beyond what the required tests need to run.
- Sanitized reviewer log-tail hardening beyond the attestation summary.
- Full evidence sealing (already routed to the separate evidence-hashing plan).

**Residual accepted by the operator:** the trimmed kernel closes the FALSE-PASS class (the actual
observed failure, SPEC-015) but leaves some self-gating hardening for later specs. This is a
conscious trade to reach a working end-to-end factory sooner.

## 4. Consequences
- PLAN-003 is re-scoped to the kernel (revision 7) and re-reviewed under the stop-rule.
- PLAN-004 keeps its dependency on corrected metrics semantics, which stay in the kernel.
- Deferred items are tracked in the baton/ledger so the trim is not silent scope loss.
