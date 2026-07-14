# PLATFORM-SPEC — the self-improving software factory (target definition)

**Status:** draft target spec (operator reframe, 2026-07-14). This is the product. The factory is
not scaffolding *for* a product; the factory IS the first product, by design (operator: "my
experience is in creating platforms; the first thing I build is a robust, self-improving platform
that can learn, iterate, improve, identify issues, and build — so the first product it builds is
itself").

Supersedes the framing (not the findings) of R25's "beautiful factory that never ships a product."
The factory can *be* the product — but only if it ships **measured capability improvements**. This
spec defines what that means and makes it falsifiable.

---

## 1. What the product IS (one paragraph)

An autonomous software platform whose defining property is a **closed improvement loop with an
external oracle**: it observes its own behaviour, identifies concrete issues and opportunities,
decides what to build under a budget, builds it through safety gates, **verifies the result against a
fixed task distribution it cannot edit**, ships the capability, and **measures the delta** — then
feeds that measurement back into the next iteration. Its first and current customer is itself; a
platform is validated by dogfooding before it is offered outward. It is "self-improving" only while
the loop is *closed* — i.e. while every iteration produces a measured capability delta. An iteration
that changes the platform without a measured delta is **accretion**, and the platform must be able to
tell the difference.

## 2. The learning loop: ACT → REACT → **REFLECT** → **REMEMBER** → REPEAT

*(Added 2026-07-14 after the operator asked "where is the reflect part?" — he was right: v1 of this
spec described a CONTROL loop (measure and correct), not a LEARNING loop. Measurement tells you the
delta. **Reflection tells you why, and what to do differently.** Without it the platform improves only
by whatever someone happens to try next; it accumulates no wisdom, and every attempt re-derives its
lessons from scratch.)*

**What we already have (a primitive Reflexion loop):** ACT = the worker attempt. REACT = deterministic
environment feedback (integrity / scope / test-attestation / reviewer verdict). REPEAT = remediation,
where "each remediation is a NEW attempt whose prompt embeds the SPECIFIC findings of the last
failure." Plus a stuck-detector: "two consecutive identical findings = stop-early."

**What is missing — the two nodes that make it learning:**

- **REFLECT** — no node distils a *lesson* from a trajectory. We pass raw findings forward, not
  "what I got wrong and the strategy to fix it."
- **REMEMBER** — memory is **amnesiac**. Lessons live only inside one spec's remediation chain and
  die with it. Cross-spec, cross-time learning is **zero**. Every new spec starts from nothing.

**Two memory tiers:**
| Tier | Scope | Today |
|---|---|---|
| **Episodic** | within one spec's remediation chain | ✅ crude (raw findings, not distilled lessons) |
| **Semantic / durable** | across specs, across time — hypothesis → outcome → lesson → *did the lesson later pay off?* | ❌ **nothing.** This is what makes the PLATFORM learn rather than one attempt learn. |

### The anti-superstition guard (non-negotiable)

Reflection is a **self-deception surface**, and adding it naively makes the platform *worse* while
feeling better. Three binding constraints:

1. **Never self-reflect.** The reflector must be the *other* vendor (Codex reflects on a Claude
   trajectory and vice versa). Self-preference bias is causally tied to self-recognition — a model
   grading its own trajectory reliably flatters it. This extends the existing never-Codex-grades-Codex
   invariant to the reflect node.
2. **Ground every reflection in deterministic environment feedback** — gate outcomes, test
   attestations, diffs — never in the agent's own account of what it did. A trajectory is evidence;
   the agent's summary of it is not.
3. **A lesson is a HYPOTHESIS, not a truth.** It is recorded as unvalidated and becomes trusted only
   if it later moves the **exogenous** capability signal (§2b). Lessons that never pay off are pruned.
   **Without this, verbal memory is a superstition accumulator** — confident, coherent, and wrong.

## 2b. The oracle must be EXOGENOUS (SOL, adversarial validation, 2026-07-14)

> *"If the platform authors the tasks, selects which tasks count, implements the change, and
> interprets the result, the loop is not externally closed. It is an internally consistent narrative
> generator. File permissions do not fix that."*

This kills the "immutable self-authored golden dataset" design in v1 of this spec. Immutability
protects test *integrity*; it does nothing for test *validity or independence*. **A benchmark the
platform wrote cannot falsify the platform.**

**The requirement is exogeneity, not immutability:** the improvement target must be something the
platform **cannot redefine to make itself look better** — a workload it did not choose and whose
acceptance criteria it cannot author or edit.

**Available today, free, and genuinely exogenous:** a public coding benchmark (SWE-bench Verified /
Polyglot) — tasks we did not write, hidden acceptance we cannot edit, comparable to published
baselines. It measures precisely the platform capability that matters: *can this factory take a task
and produce working code?* Plus objective internal constraints that also cannot be argued with
(cost per task, wall-clock, crash rate, escaped-defect rate).

**And it is what makes REFLECT safe:** reflection proposes lessons; the exogenous benchmark decides
which ones were real. Reflection without an exogenous target is superstition. An exogenous target
without reflection is measurement without learning. **Both, or neither works.**

## 2c. The improvement loop (stages)

The platform is self-improving iff the loop *closes* — stages 1, 2, 7, 8 exist and gate the rest, and
the REFLECT/REMEMBER nodes above run inside it. Today it runs 4–6 well and 1/2/7/8 barely or not at all.

| # | Stage | Invariant that makes it improvement (not just change) |
|---|---|---|
| 1 | **OBSERVE** | Every run emits telemetry (cost, wall-clock, gate outcomes, escapes, dogfood results) as read-only evidence. No run is invisible. |
| 2 | **EVALUATE (the ORACLE)** | The platform is run against a **fixed, versioned task distribution it cannot modify**, yielding a capability signal (accuracy + safety, separately). This is the convergence test. |
| 3 | **IDENTIFY** | Issues/opportunities are named from telemetry + eval regressions + **validated lessons in durable memory** — not from a human's hunch alone. |
| 4 | **PRIORITIZE** | What to build next is chosen under an explicit **budget** (tokens/$, attention). |
| 5 | **PLAN** | Decompose to specs. Depth scales with uncertainty/blast-radius (R26), not ceremony. |
| 6 | **BUILD** | Isolated worker → integrity/scope/test gates → cross-vendor review → PR. (The current asset.) |
| 7 | **VERIFY vs ORACLE** | A change ships only if it holds-or-improves the capability signal AND regresses no safety counter — measured against stage 2, not just its own unit tests. |
| 8 | **SHIP + MEASURE** | Release a capability; record the **delta** vs the prior baseline **on the exogenous benchmark**; **promote or prune the lessons that predicted it**; feed back to stage 1. |

**The governing invariant (machine-checkable form of the anti-accretion rule):**
> Every loop iteration must produce a measured capability delta against the oracle. An iteration
> that mutates the platform but does not move-or-hold the capability signal is flagged as accretion.

This is the same shape as the fixes already shipped: T1 ("a change that can't demonstrate its tests
ran doesn't count") and PLAN-006's value-floor ("only externally-meaningful transitions count"). The
oracle is the platform-level version of the same discipline.

## 3. Definition of "shipped" for a platform

A **capability release**: a merged, reviewed change to the platform that (a) names the issue/opportunity
it addresses, (b) was verified against the oracle, (c) recorded a capability delta, (d) did not
regress a safety counter. Merging to `integration` is necessary, not sufficient — without (b)–(d) it
is a change, not a capability release.

## 4. Non-goals / anti-accretion boundaries (what this is NOT)

- NOT a platform that improves itself with no forcing function. Self-modification without an oracle
  is the failure this spec exists to prevent (two-day accretion, 2026-07-13/14).
- NOT a governance-artifact generator. Planning depth scales with blast radius (R26).
- NOT (yet) a multi-product idea factory. The 10-stage VISION (idea→deploy→maintain of arbitrary
  products) is the *eventual* goal; the platform itself is product #1 and its loop must close first.
- NOT built past what the oracle justifies. Cryptographic measurement journals, activation state
  machines, best-of-N choosers, trained critics — all deferred until a real capability regression
  demands them (per the mini-swe-agent lesson: ship the loop, measure, THEN add machinery).

## 5. Success criteria (falsifiable)

1. The loop **closes**: one real issue travels stage 1→8 and records a capability delta.
2. A change that regresses the oracle's safety counter is **blocked at stage 7**, demonstrably.
3. The accretion detector fires: an iteration with no capability delta is flagged, not merged as
   progress.
4. Cost per capability release is recorded (stage 1/4), so the platform knows what it spends to
   improve.
5. The oracle is **EXOGENOUS** — the platform did not author the tasks and cannot edit the acceptance
   criteria (SOL: immutability protects integrity, not validity; a benchmark we wrote cannot falsify
   us). Immutability to the *worker* (T1b) is necessary but not sufficient.
6. **Reflection is cross-vendor and evidence-grounded**, and a lesson is quarantined as a hypothesis
   until the exogenous signal validates it. A demonstrable superstition — a lesson that never paid
   off — must be prunable, and pruned.
7. **A preregistered baseline exists before any capability claim.** No retroactive success
   definition: state the target, the workload, and the cost ceiling BEFORE the work, or the result
   does not count (SOL's "tell" for rationalization).

## 6. Provenance
Operator reframe 2026-07-14. This is a stage-1 product bet → warrants dual-vendor adversarial
validation before it governs work (R26 moves that rigor here). Gap assessment: R27.
