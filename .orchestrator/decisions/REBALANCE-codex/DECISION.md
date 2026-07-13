# REBALANCE-codex — delegate-first execution split (Claude delegates, Codex executes most work)

**Trigger:** non-trivial control-plane, **Critical** tier (governing operating policy + trust-boundary
implications). Dual-validated: Claude plan (`plan.md`) + independent adversarial SOL pass
(`prompt.txt` → `sol-response.txt`, gpt-5.6-sol, reasoning=high).

## SOL verdict: BLOCK → PASS-on-conditions
SOL endorsed the direction ("dogfooding is better than unreviewed Claude-direct edits") but blocked
until four invariants are added. All four are accepted (no disagreement to escalate). Dispositions:

1. **Bootstrap invariant (ACCEPTED, was missing).** *A change to the orchestrator's trust boundary
   must never validate, approve, review-bind, or merge itself.* The installed **parent** version runs
   isolation/integrity/scope/test/review/merge on the candidate; the candidate does not become active
   until separately approved and installed. Largely satisfied already (a PR's code can't gate itself —
   the merged/installed version does; workers can't self-approve), but now made **explicit + guarded**:
   the dispatcher must never execute a candidate's own modified gate/dispatch code to gate that
   candidate.
2. **Classify by capability + transitive dependency, NOT path-touch (ACCEPTED — my rule was too weak).**
   A shared helper, config, dependency pin, test fixture, shell wrapper, or import can alter trusted
   behavior without touching a named core path. Adopt a **machine-enforced trust manifest** + dependency
   closure; any file in the trust closure, or any unclassified/ambiguous file, is forced **high-risk**
   (fail closed).
3. **Codex may author trust-critical code via a high-assurance lane (ACCEPTED — this delegates MORE,
   which the operator wants).** Reserve Claude/human for *final authorization + independent review*,
   "not necessarily keystrokes." Trust-critical work gets: parent-version validation + a pre-dispatch
   spec challenge + mandatory human approval + adversarial SOL design review + security regression
   tests + staged activation.
4. **Independence gap + metric-as-perverse-target (ACCEPTED).** Add a **pre-dispatch spec challenge**
   (fresh, context-isolated critic — not the implementation conversation — surfaces missing abuse cases
   and invariant-level acceptance tests) for medium/high-risk work; keep post-impl review Claude-only
   (never Codex-grades-Codex). Do **not** ship a single delegation ratio as a target; report
   **risk-weighted work class**, fail closed on unclassified files, never set a quota target on the
   trust-critical lane. Research fan-out to Codex must include **source capture + claim-level
   reconciliation** ("vendor diversity without evidence diversity is cosmetic").

## Final design — THREE lanes (SOL's structure, adopted)
- **Ordinary delegated lane** (default for most work): Codex implements → deterministic gates →
  independent Claude review → PR → auto-merge to `integration`. Metrics, reporting, non-normative docs,
  isolated helpers, and research execution live here.
- **High-assurance delegated lane** (trust-critical code): Codex *may* author, but parent-version
  validates; mandatory spec challenge + human approval + SOL design review + security regression tests
  + staged activation.
- **Control-plane authorization lane** (Claude + human judgment, never delegated): policy changes, trust
  classification, reviewer conclusions, merge authority, final synthesis, dual-vendor reconciliation.

## Status
Revised plan = `plan.md` + this disposition. **Confirmatory SOL pass on the amended design:
`VERDICT: PASS` (`sol-confirm.txt`).** Both vendors now agree with no unresolved blocker — dual
validation complete. **Operator ratification still required** (Critical, changes operating policy)
before encoding in CLAUDE.md and building the trust-manifest / spec-challenge / risk-weighted-metrics
pieces.
