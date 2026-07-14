# Claude challenge — PLAN-003 (Phase 1: verdict integrity + metrics semantics), revision of 2026-07-14T05:42:58Z

Reviewer: Claude (orchestrator), fresh read of the full draft against the live tree at
`integration` HEAD. Verdict: **REVISE** — the plan's substance is sound and correctly reconciles the
VERDICT-INTEGRITY investigation, but two objections are invariant-level and blocking; three are
non-blocking but require disposition. Evidence citations verified on this host before drafting
(schema `minItems:1` at scripts/verdict.schema.json:10; UNMET-only PASS rejection at
scripts/dispatch.py:1114; "exited 0" reviewer evidence at scripts/dispatch.py:1187; skip-as-pass at
scripts/test:22; SPEC-015/1 test.log:7,10,30 + review.json 7/7 MET).

## O1 (clerical, BLOCKING for digest binding) — plan self-identifies as PLAN-002

The body header says `id: PLAN-002` / "# PLAN-002 — Phase 1 …" while the allocated artifact and YAML
frontmatter are PLAN-003; PLAN-002 already exists (self-reflection). Authorization is digest-bound;
an artifact whose body claims another plan's identity cannot be the bound revision. Fix the body to
PLAN-003 everywhere and drop the duplicated pseudo-frontmatter block (the real frontmatter is the
YAML at the top).

## O2 (design gap, BLOCKING) — attestation is forgeable by candidate-edited required tests

The required trust-suite tests execute **from the candidate worktree**. A candidate whose allowed
paths legitimately include `tests/` (Dispatch 2's own allowed paths do!) can rewrite
`tests/dispatch_gate4.sh` into a stub that emits well-formed passing assertion events (it receives
the run nonce via injected environment, §4.4 step 3) and exits 0. The attestation then certifies
"required test ran, N assertions, PASS" — machine-signed, but vacuous. §7 covers "candidate removes
or renames a required test" and assumption 5 acknowledges semantic limits, but the plan nowhere
addresses **content substitution of a required test**. The reviewer seeing the diff is exactly the
backstop SPEC-015 proved insufficient; Phase 1's premise is machine enforcement.

Required disposition: choose and specify a mechanism, e.g. (a) execute required trust-suite tests
from the **installed parent / base_sha content** (regression discipline: base tests judge candidate
code; candidate-modified copies of required tests run additionally but never satisfy attestation), or
(b) any diff touching a required-test file forces fail-closed escalation (mandatory human
authorization naming the test change). State the edge case handling for specs whose legitimate
purpose is updating a required test, and add the failure-mode row.

## O3 (validation gap) — assertion-event migration fidelity is unproven

Step 7 migrates every tracked `tests/*.sh` to emit assertion events, and assumption 4 declares this
mechanical. A mis-migrated test (event emitted before the condition is evaluated, or `ok:true`
unconditional) silently defeats the zero-assertion protection while keeping everything green — the
exact failure shape this plan exists to kill. Add an acceptance criterion: for a sample (or all) of
migrated tests, an induced failure of the guarded condition must produce `ok:false` + nonzero exit
(a mutation drill proving events are wired to real conditions), executed at least once in Dispatch
2's validation.

## O4 (reviewability) — Dispatch 2's diff is too broad for one high-assurance review

Dispatch 2 touches dispatcher gate logic + new runner + policy + setup-worker + CI + **every tracked
test file**. One reviewer pass over that diff dilutes exactly the review attention the change is
meant to restore. Disposition requested: split the mechanical migration (assertion events + exit-77
conversion across `tests/*.sh`, no behavior change) into a predecessor spec (still high-assurance —
tests are in the trust closure — but a homogeneous, cheaply reviewable diff), leaving Dispatch 2 as
gate logic only. If you reject the split, justify why one review pass over a heterogeneous ~20-file
trust-critical diff is acceptable under the SPEC-015 lesson.

## O5 (invariant conflict, BLOCKING) — Dispatch 1 is "ordinary" but touches scripts/dispatch.py

CLAUDE.md REBALANCE invariant 2 forces **any file in the trust closure to high-risk, fail closed** —
classification is by capability/dependency, not by which functions the diff intends to touch. The
scope gate enforces paths, not function boundaries, so "scripts/dispatch.py, limited to the metrics
reporting path" is not machine-enforceable: an ordinary-lane worker with dispatch.py in allowed
paths can modify gate code. Disposition options: (a) extract `cmd_metrics`/reporting helpers into a
new standalone `scripts/metrics_report.py` (read-only over evidence, outside the gate path; thin
alias retained or removed per truth-in-docs) so Dispatch 1's allowed paths exclude dispatch.py
entirely; or (b) reclassify Dispatch 1 as high-risk with the operator approval artifact. (a) is
preferred — it also serves Phase 2, whose collector wants exactly that read-only reporting surface.

## Minor (no disposition required, note only)

- §4.10.5 says "JSON Schema cannot bind a dynamic list" — correct here, but note the dispatcher
  could generate a per-attempt schema (as it already pins verdict.schema.json per attempt); the
  chosen dispatcher-side validation is still the better mechanism, just don't claim impossibility.
- "additionalProperties: false where applicable" (§6.17) — enumerate where it is NOT applicable in
  the spec text, or the implementer will decide.
- R6.3's fixture arithmetic is verified consistent (numerator 1 / denominator 3).

## Process note

Dispatches 2 and 3 are high-risk: each requires the operator's per-dispatch approval artifact
(`approvals/<digest>.attempt-<n>.json`) at every autonomy level. Dispatch 1's lane depends on the O5
disposition. After disposition, the revised PLAN-003 goes to a fresh-context SOL adversarial
critique (same revision Claude authorizes) before authorization.
