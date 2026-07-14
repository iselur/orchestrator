# DECISION — adopt the R25 path (freeze the control plane, ship truth fixes, point at a product)

**Authority:** operator, 2026-07-14 ("Ok let's do A"), after the dual-vendor R25 architecture review.
**Tier:** control-plane. Supersedes the R24 sequencing where they conflict.

## Binding

1. **The control plane is FROZEN.** PLAN-003 (halted, rev9), PLAN-004 (parked, rev6), PLAN-006 (held,
   rev3) are CLOSED AS SCOPED. Their artifacts and findings are preserved on disk, not deleted.
   PLAN-005 stays authorized but its break-glass apparatus is CUT (see 3).
2. **NEW GOVERNING RULE (replaces speculative hardening):**
   > The control plane may not be improved except in response to a failure that a real product
   > shipment actually hit. The factory earns each new gate by breaking without it.
3. **Ship two truth fixes by hand.** One PR each, NO plan ceremony, NO dual-vendor loop:
   - **T1 — SKIP != PASS.** Required tests must actually execute and pass. Includes the round-10
     finding that survives all scoping: an EMPTY required-test set must fail closed (a non-empty set
     and >=1 executed assertion are mandatory), never produce a vacuous consistent "pass".
   - **T2 — isolation fail-closed.** `isolation_available()` false => refuse before durable state and
     before any worker-controlled code. Break-glass = a plain env var that the operator types
     knowingly; NO root secret, NO single-use token, NO scoped sudoers, NO redemption ledger.
   - **T3 (free, same PR class) — truth-in-docs.** README's "green tests are never mistaken for a met
     spec" is currently FALSE. Fix it and the other dangling claims.
4. **Planning depth scales with uncertainty, reversibility, and blast radius** — NOT with the word
   "substantive". The "brief-caliber plan for every substantive task" rule is REVOKED.
5. **Dual-vendor adversarial rigor MOVES to stage 1** (ideas, product bets, irreversible decisions),
   where being wrong costs a quarter. It is NOT applied to internal mechanisms.
6. **Then: name a product, give it its own repo, push ONE real feature through the whole chain** —
   lifecycle object -> Linear ticket -> spec -> PR -> deploy -> uptime check. Deliberately shabby.
7. **Instrument the binding resource** (tokens/quota/wall-clock/cost per shipped outcome) — the thing
   that actually killed the overnight loop.

## Preserved findings (must survive into whatever replaces the closed plans)
- `decisions/PLAN-003-verdict-integrity/HALTED-pending-operator.md` (incl. the empty-set finding)
- `decisions/R23-continuation-failure/HELD-pending-operator.md` (the 8 load-bearing loop findings)
- `decisions/PLAN-004-measurement/PARKED.md`
- `decisions/R25-architecture-review/` (both reviews + cited loop research)
