## Overall verdict

The factory has a substantial, safety-oriented **spec-to-PR control plane**, but it is not yet the end-to-end AI engineering factory described in the vision.

Using “BUILT” only for operationally demonstrated capabilities:

- **BUILT:** 2 stages
- **PARTIAL:** 6 stages
- **MISSING:** 2 stages

The implementation is concentrated in stages 5–8. Idea intake, external ticketing, deployment, and product maintenance remain largely outside the system.

## 1. Lifecycle coverage matrix

| # | Lifecycle stage | Status | Evidence and judgment |
|---|---|---|---|
| 1 | Grill the idea | **PARTIAL — EVIDENCE-LIMITED** | `CLAUDE.md` defines independent Claude breadth research, independent Codex/SOL research, falsification, source capture, and reconciliation. Relevant directories exist at `.orchestrator/decisions/IDEAS-*`, `R20-loop-design/`, and `R21-pocock-skills/`. But R20/R21 remain open, their contents are not in the bundle, and there is no evidenced general intake command or repeatable idea-grilling workflow that turns an arbitrary idea into a completed research package. |
| 2 | Review / decide | **BUILT** | The dual-validation decision process is real and repeatedly used: [`CLAUDE.md`](/home/val/orchestrator/CLAUDE.md), `.orchestrator/decisions/PLAN-dual-validation/`, `REBALANCE-codex/`, and `REINFORCE-delegation-planning/`. It supports adversarial PASS/BLOCK review, dispositions, revision binding, escalation of disagreement, and presentation to the operator. Authority records are stale in places, but the core decision capability exists. |
| 3 | Break down into tickets/specs | **PARTIAL** | Real plans, schema-validated specs, dependencies, approvals, and the Codex plan authoring helper exist: [`scripts/codex-plan`](/home/val/orchestrator/scripts/codex-plan), [`specs/spec.schema.json`](/home/val/orchestrator/specs/spec.schema.json), `.orchestrator/plans/`, and `SPEC-001`–`SPEC-016`. What is missing is an evidenced general transformation from a reconciled idea into a complete ticket DAG, including dependency analysis, acceptance criteria, deployment work, and maintenance work. `plan_ref` is still promised rather than enforced. |
| 4 | Log tickets in Jira / Linear | **MISSING** | No Jira/Linear adapter, API client, synchronization state, external ticket identifiers, or tracker reconciliation mechanism appears in the bundle. `.orchestrator/REQUEST-LEDGER.md` is an internal request log, not the tracking-system capability named by the vision. |
| 5 | Iteratively improve the plan | **BUILT** | Draft → Claude challenge → SOL BLOCK/PASS → dispositions → revised plan → authorization is operationally demonstrated. Evidence includes `.orchestrator/plans/PLAN-001.md`, `PLAN-003.md`, `PLAN-004.md`, and `.orchestrator/decisions/PLAN-003-verdict-integrity/`, `PLAN-004-measurement/`, and `PLAN-005-isolation-failopen/`. The mechanism is artifact-heavy and partly manual, but genuine iteration exists. |
| 6 | Iteratively execute | **PARTIAL — EVIDENCE-LIMITED** | The strongest implementation area: `launch`, `await`, `cancel`, `health`, `reconcile`, bounded remediation, parallel attempts, stale-base refusal, merge, and integrate are represented in [`scripts/dispatch.py`](/home/val/orchestrator/scripts/dispatch.py), tests, attempts, state, and escalation records. It is not safely complete: known isolation fail-open behavior, uncovered merge paths, missing machine-enforced trust classification, incomplete approval validation, orphan evidence, and the false test certification all weaken the promised execution boundary. Exact enforcement cannot be verified without the full code. |
| 7 | Review results | **PARTIAL** | Independent Claude review, structured verdict schema, diff/evidence binding, and fail-closed intent exist in [`scripts/verdict.schema.json`](/home/val/orchestrator/scripts/verdict.schema.json), dispatcher review handling, and `.orchestrator/attempts/`. But `VERDICT-INTEGRITY/response.md` found one false PASS among fourteen: the reviewer certified tests it could not see had skipped. Criterion count/text binding and mechanical blocker handling are also not yet implemented. |
| 8 | Test it: deterministic gates + golden evaluation | **PARTIAL** | A repo suite, per-spec `test_command`, CI, isolation tests, and gate tests exist under [`tests/`](/home/val/orchestrator/tests) and [`.github/workflows/ci.yml`](/home/val/orchestrator/.github/workflows/ci.yml). However, SKIP currently can masquerade as PASS for required tests, isolated workers cannot access needed dependencies in some tests, and the golden dataset/evaluation matrix is only planned in `PLAN-004` and `MEASUREMENT-layer/`. |
| 9 | Set it up running: deploy / operate | **MISSING** | The repository can operate the orchestrator itself on a VPS, but there is no evidenced product deployment lifecycle: no deploy command, release artifact model, environment promotion, secrets/configuration interface, rollout, rollback, service health verification, or deployment evidence binding. Opening or merging a PR is not deployment. |
| 10 | Maintain it | **PARTIAL — EVIDENCE-LIMITED** | `dispatch health`, `reconcile`, the continuation timer, reminders, and tracked pending work provide narrow maintenance of the factory itself. Evidence: `.orchestrator/continue-session.sh`, `continue-logs/PENDING`, and the dispatcher health/reconcile commands. There is no service inventory, monitoring/SLO system, incident loop, dependency/security upkeep, scheduled maintenance policy, or autonomous maintenance of a deployed product such as EVA. Live timer verification is explicitly still pending. |

## 2. Mismatches with the vision

### Direct contradictions

- **Claude’s role has been narrowed below the vision.** The vision says Claude and Codex are both architects, executors, and management capacity. `CLAUDE.md` instead reserves Claude primarily for orchestration, authorization, synthesis, and review, while prohibiting it from taking over implementation. That may be a sound trust policy, but it is not the stated role model.

- **The system starts at a spec, not at an idea.** The README’s real product is “write a small spec, approve it, receive a PR.” The vision starts several stages earlier with arbitrary idea intake, adversarial research, decision-making, and decomposition.

- **The lifecycle ends at integration.** The vision continues through deployment, operation, and maintenance. The dispatcher ends at merge/integrate.

- **External ticket tracking is explicitly required but absent.** Considerable effort has gone into an internal request ledger while Jira/Linear integration is nonexistent.

- **Safety claims overstate observed reality.** The README says green tests are never mistaken for evidence and workers never touch credentials. The ledger records a false PASS caused by skipped tests, plus a residual worker-readable Codex token and isolation fail-open work still underway.

- **Machine-enforced trust classification is claimed before it exists.** `CLAUDE.md` calls for a capability/dependency trust manifest, while `continue-logs/PENDING` says this is unbuilt and classification is currently policy/manual.

- **Recorded project state is internally inconsistent.** R09 is `done` in the ledger table but `OPEN` in its watchlist; R18 is `done` in the table but grouped as `IN-PROGRESS`. Stale decision authority records are also acknowledged. A management system cannot reliably orchestrate a long lifecycle if its own canonical state is ambiguous.

### Architectural over-shoot

The project has invested deeply in:

- self-development bootstrap verification;
- root-owned installed snapshots;
- approval digests and activation manifests;
- template/bootstrap publication;
- evidence hashing and provenance;
- delegation metrics and process audits;
- elaborate per-request planning ceremony.

Much of this supports safe execution, but it is disproportionately advanced relative to the missing idea intake, tracker, deployment, and maintenance capabilities. In effect, the factory is heavily optimizing the middle of the lifecycle before establishing the full lifecycle.

`PLAN-003` is the clearest example. A frozen Dispatch 0 plus six staged dispatches may repair the bootstrap problem, but it also risks creating a second control plane whose correctness and maintenance burden rival the original. An installed-parent release boundary is necessary; the chosen implementation should be reduced to the smallest mechanism that prevents candidate code from certifying itself.

### Architectural under-shoot

- No first-class lifecycle object links **idea → research → decision → plan → ticket → attempt → PR → release → running service → maintenance event**.
- No generic idea intake or research result schema.
- No external ticket synchronization.
- No deployment or release abstraction.
- No product/service inventory.
- No ongoing operational feedback loop.
- No completed golden evaluation layer.
- No representative real multi-file feature or bugfix proving that the factory works beyond toy helpers.
- Worker execution is software-repository-specific and network-off, which constrains the claim that the operator can drop “any idea” into it.

## 3. Prioritized missing pieces

| Priority | Missing piece | Build sketch | Effort |
|---|---|---|---|
| 1 | Restore truthful trust gates | Establish a minimal installed-parent verifier that mechanically requires every selected test/assertion to execute and pass; bind review, base, approval, and candidate identities; fail closed when isolation is unavailable. Avoid expanding Dispatch 0 beyond this bootstrap boundary. | **L** |
| 2 | Canonical lifecycle spine | Define durable, versioned entities and transitions for Idea, Research, Decision, Plan, Ticket, Attempt, Release, Service, Incident, and Maintenance Task, with one identifier chain and explicit authority at each transition. | **L** |
| 3 | Repeatable idea-grilling workflow | Add an intake command that creates two isolated vendor research assignments, requires claim-level sources and falsification attempts, then emits a reconciled recommendation or explicit disagreement for the operator. | **M** |
| 4 | Ticket decomposition and tracker sync | Generate a dependency-aware ticket DAG from an authorized decision, then create/update Jira or Linear issues idempotently while storing external IDs and detecting drift. | **M** |
| 5 | Enforced plan lifecycle | Implement plan revision/digest state, `plan_ref` in specs, challenge dispositions, authorization, and automatic invalidation when material scope, risk, validation, or rollback assumptions change. | **M** |
| 6 | Honest golden evaluation | After test integrity is repaired, implement the sealed golden tasks, planted defects, pairwise configuration evaluation, safety/accuracy scoring, and semantic-epoch separation described by `PLAN-004`. | **M** |
| 7 | Deployment and release plane | Introduce a target adapter contract for build artifacts, environment configuration, secret references, staged rollout, health verification, rollback, and release evidence bound to the reviewed commit. | **L** |
| 8 | Operations and maintenance loop | Add a service registry, health/SLO checks, alerts, incident records, scheduled dependency/security upkeep, remediation tickets, and human escalation boundaries. | **L** |
| 9 | One representative end-to-end pilot | Run a real multi-file feature or bugfix from idea intake through external tickets, execution, review, golden checks, deployment, and a scheduled maintenance event; use its failures to simplify the architecture. | **M** |
| 10 | Truth and authority cleanup | Reconcile the ledger/watchlist, stale decision verdicts, orphan attempts/branches, live timer evidence, missing-document references, parallelism claims, and README safety language before presenting the system as production-ready. | **S–M** |

## 4. Single biggest risk

The biggest risk is **recursive control-plane accretion becoming the product**.

The evidence already shows many concurrent plans, audits, bootstrap mechanisms, authority repairs, measurement designs, and self-hosting concerns, while no representative product has traveled through all ten stages. Every additional trust mechanism creates more code that itself needs classification, approval, testing, activation, evidence, and maintenance.

If that continues, the factory can become extraordinarily sophisticated at governing its own incomplete middle stage without ever becoming the operator’s idea-to-maintained-system factory. The corrective is not to abandon the trust boundary; it is to stabilize the smallest truthful execution kernel, then immediately prove a thin end-to-end lifecycle with real work before adding further control-plane sophistication.

REVIEW COMPLETE
