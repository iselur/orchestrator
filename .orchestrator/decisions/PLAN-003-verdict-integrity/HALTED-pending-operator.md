# PLAN-003 — iteration HALTED at revision 9 (2026-07-14), pending operator decision

**Not authorized. Not abandoned. No rev10 launched.**

## Why the loop was stopped rather than continued

Round 10 (rev9) returned BLOCK with 3 further findings — the same shape as rounds 1-9:
12 → 4 → 3 → 4 → 1 → 1 → 3. Each round finds real defects. Each fix enlarges or complicates the
mechanism. The mechanism is a second control plane defending the first against a compromised
operator-UID orchestrator — i.e. against the operator himself — on a single-tenant box whose only
user is the owner.

The R25 dual-vendor architecture review (delivered to the operator 2026-07-14,
`decisions/R25-architecture-review/`) independently identified this exact loop as the factory's
central pathology and named PLAN-003 as its clearest instance. Both vendors recommended:

> Replace PLAN-003 as scoped with the ~50-line SKIP != PASS test-attestation fix, hand-written, one
> PR, no plan ceremony. The rest of the mechanism (root-owned launcher, installed-parent attestation,
> blob-verified parent-content tests, choke point) defends against threats this operator does not
> have, and each new gate creates the next high-assurance plan.

Firing rev10 while holding a report that names this loop as the problem would be the pathology
performing itself. So: HALT, surface, wait.

## The one finding worth carrying forward regardless of the decision

Round-10 finding 1 is genuinely load-bearing and survives ANY scoping decision:
> The parent policy can select an EMPTY required-test set, producing zero invocation records and an
> internally consistent empty aggregate — a vacuous pass.
Any implementation of test attestation, however small, MUST require a non-empty selected required-test
set (and therefore >= 1 expected assertion), or emit `failed_test` before review. Carry this into the
minimal fix.

## Operator decision (open)
- **(A) R25 path (both vendors recommend):** close PLAN-003 as scoped; hand-write SKIP != PASS
  (~50 lines + the non-empty-set rule above) and isolation fail-closed; redirect the factory at a
  real product.
- **(B) Continue:** authorize rev10+ and keep hardening. Cost: unbounded rounds, no product.

Recorded findings from rounds 1-10 are preserved in this directory for whoever resumes.
