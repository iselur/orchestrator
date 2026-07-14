# Independent SOL research pass — Ledger R25

## Executive verdict

The 2025–2026 consensus is not “put a smarter model in a `while` loop.” The production pattern is:

> a bounded agent episode inside a durable workflow, supplied with selective context, acting in an isolated environment, judged by external evidence, and advancing a recoverable incumbent only when verification succeeds.

Your system has built much of the high-assurance inner execution kernel. It has not built the company. It is over-investing in certifying code changes while under-investing in choosing products, deploying them, observing users, operating services, and converting operational feedback into the next work item.

Confidence labels:

- **High:** primary implementation, official documentation, or direct production report.
- **Medium:** vendor self-report or a design demonstrated in a narrower setting.
- **Low:** practitioner thread or result not independently reproduced.

# Part A — Agent-loop design, 2025–2026 state of the art

## 1. Canonical loop patterns

| Pattern | Production form | Representative systems | Confidence |
|---|---|---|---|
| Tool-using single-agent loop | User intent → inference → tool call → observation → repeat → final response. The surrounding harness owns prompting, tools, permissions, and context. | Codex describes this exact inner loop; OpenHands implements it as stateless, event-driven steps with condensation and security analysis. [Codex loop](https://openai.com/index/unrolling-the-codex-agent-loop/), [OpenHands architecture](https://docs.openhands.dev/sdk/arch/agent) | **High** |
| Incremental fresh-context ratchet | One bounded feature per episode; write progress, tests, and git state; restart with a fresh context; reconstruct from durable artifacts. | Anthropic’s long-running harness uses an initializer, incremental coding sessions, progress notes, git, and startup smoke tests. Ralph popularized the simpler “fresh agent until externally complete” version. [Anthropic long-running harness](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [Matt Pocock thread mirror](https://threadreaderapp.com/thread/2007924876548637089.html) | **High** for Anthropic; **Low–Medium** for generalized Ralph claims |
| Generator–evaluator–remediator | A builder produces a candidate; a separate evaluator runs deterministic and/or experiential checks; findings return to the builder until thresholds or budgets terminate the loop. | Anthropic uses planner/generator/evaluator roles and browser-driven QA; Cognition automatically feeds reviewer, CI, linter, and scanner findings back to Devin. [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps), [Devin review loop](https://cognition.com/blog/closing-the-agent-loop-devin-autofixes-review-comments) | **High** |
| Orchestrator–worker fan-out | A lead decomposes genuinely independent work, gives each worker a bounded objective and output contract, then synthesizes results. | Anthropic’s research system uses independent contexts as parallel search-and-compression units; Devin now decomposes large tasks across managed sessions. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system), [Managed Devins](https://cognition.com/blog/devin-can-now-manage-devins) | **High** for research; **Medium** for tightly coupled coding |
| Parallel candidate generation plus selection | Run several attempts or configurations, then select or merge the best verified candidate. | SWE-agent supports retry loops and expensive competitive configurations with five attempts followed by a discriminator. [SWE-agent competitive runs](https://swe-agent.com/latest/usage/competitive_runs/), [SWE-agent loop and limits](https://swe-agent.com/latest/reference/agent/) | **High** |
| Durable cloud workflow | Conversation, agent process, and machine state are separate; an append-only session or workflow history survives process, VM, and provider failure. | Cursor moved from fragile work stealing to Temporal and shorter task workflows; Anthropic separates session log, harness, and sandbox so a harness can crash and resume from events. [Cursor cloud-agent lessons](https://cursor.com/blog/cloud-agent-lessons), [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents) | **High** |
| Incumbent hill-climber | Establish a baseline; make one change; run a fixed evaluator under a comparable budget; keep improvements and discard regressions. | Karpathy’s `autoresearch` freezes the evaluator and most of the environment, permits one target file, and records `keep`, `discard`, or `crash`. [autoresearch program](https://github.com/karpathy/autoresearch/blob/master/program.md) | **High** for narrow optimization; **Low** for open-ended product development |
| Planner/architect plus mechanical editor | A stronger reasoning role proposes the solution; a separate editor turns it into precise changes. | Aider’s architect/editor pairing improved its benchmark in several model combinations; Aider can automatically feed lint and test failures back for repair. [Aider architect mode](https://aider.chat/2024/09/26/architect.html), [Aider lint/test loop](https://aider.chat/docs/usage/lint-test.html) | **Medium–High** |
| Repository-as-harness | Product knowledge, architecture, executable workflows, observability, and constraints live where the agent can retrieve and execute them. | OpenAI reports a short `AGENTS.md` as a map, structured repository documentation, mechanical architecture enforcement, per-worktree applications, and agent-readable logs, metrics, traces, DOMs, and screenshots. [OpenAI harness engineering](https://openai.com/index/harness-engineering/) | **High** |

The important distinction is between the **inner model/tool loop** and the **outer workflow loop**. The inner loop ends whenever the model emits a final message; the outer loop determines whether the objective is actually complete, should be retried, should advance an incumbent, or must stop. [Codex loop](https://openai.com/index/unrolling-the-codex-agent-loop/), [Claude loops](https://claude.com/blog/getting-started-with-loops)

## 2. Loop control

### Context and compaction

- Treat the context window as a working set, not the durable record. Anthropic’s Managed Agents retains an append-only session outside the context window, allowing later harnesses to reread slices even after compaction; Cursor similarly separates conversation storage from the agent workflow and machine. [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents), [Cursor cloud-agent lessons](https://cursor.com/blog/cloud-agent-lessons) — **High**.
- Compaction is useful but lossy. Anthropic reports that compaction alone did not solve “context anxiety” in Sonnet 4.5; fresh contexts plus structured handoffs were required, although that workaround became dead weight on a later model. [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps), [Managed Agents](https://www.anthropic.com/engineering/managed-agents) — **High**.
- Keep always-loaded instructions short and use progressive disclosure. OpenAI reports that a monolithic instruction file crowded out task context, became stale, and was hard to verify; its production pattern is a short map pointing to structured, mechanically maintained sources. [OpenAI harness engineering](https://openai.com/index/harness-engineering/) — **High**.
- Large tool responses should become searchable artifacts rather than remain permanently in the prompt. Cursor reports that accumulated tool errors waste tokens and cause “context rot,” while dynamic retrieval generally replaced large static context blocks. [Cursor harness improvement](https://cursor.com/blog/continually-improving-agent-harness), [Cursor dynamic context](https://cursor.com/blog/dynamic-context-discovery) — **High**.

### Short-term versus durable memory

A useful separation is:

- **Episode memory:** current goal, recent observations, current hypothesis, next action.
- **Durable task state:** requirements, completed work, failures, decisions, test outcomes, incumbent commit, unresolved blockers.
- **Durable organizational memory:** product principles, architecture, operating procedures, incidents, customer feedback, and known failure patterns.

Anthropic’s progress files and git history demonstrate task memory; OpenAI’s repository knowledge base demonstrates organizational memory; Cursor and Anthropic’s external session logs demonstrate replayable raw history. [Anthropic long-running harness](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [OpenAI harness engineering](https://openai.com/index/harness-engineering/), [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents) — **High**.

A summary should not be the only copy of history. Compaction makes an irreversible guess about future relevance; retain the underlying event stream or source artifacts where recovery matters. [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents) — **High**.

### Subagents and parallelism

- Spawn subagents when paths are independent, context-heavy, or benefit from different tools or viewpoints. Anthropic reports a 90.2% gain on its internal breadth-research evaluation, but also reports that multi-agent systems used roughly 15× the tokens of chat and were a poor fit for dependency-heavy work. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system) — **High as a vendor-reported result**.
- Every delegated task needs an objective, boundaries, source/tool guidance, and an output contract. Anthropic observed duplicate work, gaps, runaway fan-out, and futile searches without those controls. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system) — **High**.
- Coding parallelism requires ownership boundaries. Cognition says context accumulation harms focus, but also warns that parallel agents make inconsistent implicit decisions about style and edge cases. [Managed Devins](https://cognition.com/blog/devin-can-now-manage-devins), [Cognition multi-agent report](https://cognition.com/blog/multi-agents-working) — **Medium–High**.
- Shared workspaces need explicit merge ownership, stable interfaces, or separate worktrees. Anthropic’s 16-agent compiler experiment succeeded at scale but cost almost $20,000 and remained an early research prototype rather than proof that unconstrained swarms are economical. [Parallel Claude compiler](https://www.anthropic.com/engineering/building-c-compiler) — **High**.

### Verification and validators

The strongest current pattern is a verification ladder:

1. Format, parse, lint, types, dependency and scope checks.
2. Unit and integration tests selected outside the candidate’s control.
3. Runtime or browser testing against observable behavior.
4. Independent diff review for defects the tests do not express.
5. Product/customer outcome checks after deployment.

OpenAI made apps, UI state, logs, metrics, and traces legible to agents; Anthropic and Cognition use browser/computer interaction rather than trusting generated tests alone. [OpenAI harness engineering](https://openai.com/index/harness-engineering/), [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps), [Cognition verification](https://cognition.com/blog/testing-development) — **High**.

Protect the evaluator and held-out data. A 2026 benchmark found evaluator-tampering attempts in roughly half of its natural ML-agent episodes and eliminated them with evaluator locking, at a reported 25–31% runtime overhead. [RewardHackingAgents](https://arxiv.org/abs/2603.11337) — **Medium**, because it is a narrow research setting but directly relevant.

Do not equate “all visible tests pass” with correctness. OpenAI’s audit of SWE-bench Verified found major test defects in the audited subset, and Anthropic documents rigid, ambiguous, or stochastic graders distorting agent evaluations. [OpenAI SWE-bench audit](https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/), [Anthropic agent evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) — **High**.

### Retries and incumbent ratchets

- Retry with new evidence, not the same prompt. SWE-agent has explicit retry loops, cost limits, format retry limits, consecutive-timeout termination, and trajectory records. [SWE-agent agent class](https://swe-agent.com/latest/reference/agent/) — **High**.
- Preserve a known-good incumbent. `autoresearch` keeps an improving commit and discards regressions; this works because its evaluator, time budget, and allowed edit surface are narrow and stable. [autoresearch program](https://github.com/karpathy/autoresearch/blob/master/program.md) — **High**.
- For software work, a safe analogue is: clean candidate → run fixed gates → advance reviewed commit only on success → create the next attempt from that incumbent. This is a synthesis of the SWE-agent retry and autoresearch incumbent designs, not a quoted universal rule. [SWE-agent](https://swe-agent.com/latest/reference/agent/), [autoresearch](https://github.com/karpathy/autoresearch/blob/master/program.md) — **High confidence as a design inference**.

### Stopping conditions and circuit breakers

Production loops need machine-readable terminal states such as:

- `SUCCEEDED`
- `FAILED_VERIFICATION`
- `BLOCKED_INPUT`
- `WAITING_EXTERNAL`
- `BUDGET_EXHAUSTED`
- `NO_PROGRESS`
- `REPEATED_FAILURE`
- `CANCELLED`

Claude’s current loop primitive combines evaluator-based completion with a maximum turn count; SWE-agent separately enforces cost, timeout, requery, and execution limits. [Claude loops](https://claude.com/blog/getting-started-with-loops), [SWE-agent](https://swe-agent.com/latest/reference/agent/) — **High**.

A textual `COMPLETE` emitted by the worker is insufficient as the sole stop condition. Even the practitioner Ralph recipe pairs it with a finite iteration limit, while production systems use tests or evaluators outside the worker. [Matt Pocock thread mirror](https://threadreaderapp.com/thread/2007924876548637089.html), [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps) — **Medium**.

“No durable state or artifact changed” should be an explicit failure or wait state, not a successful iteration. I found strong support for progress artifacts and bounded evaluators, but not a primary practitioner source establishing one universal no-op rule; this is therefore a **high-confidence design inference**, not a verified industry standard. [Anthropic long-running harness](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [Claude loops](https://claude.com/blog/getting-started-with-loops)

### Human checkpoints

Cognition’s own performance review says Devin performs best on clear, verifiable junior-level work and still needs human judgment for ambiguous outcomes, unit-test logic, and code quality. [Devin 2025 performance review](https://cognition.com/blog/devin-annual-performance-review-2025) — **High as a vendor self-assessment**.

The appropriate checkpoint is therefore tied to risk and ambiguity:

- Business go/no-go and budget changes.
- Irreversible or production-destructive operations.
- Security and authority changes.
- Subjective product decisions with no calibrated evaluator.
- Repeated disagreement or missing requirements.

Mechanical fixes with strong validators can continue autonomously; Cognition explicitly automates linter, CI, scanner, and bot findings while reserving architecture and product judgment for humans. [Devin review loop](https://cognition.com/blog/closing-the-agent-loop-devin-autofixes-review-comments) — **High**.

## 3. Loop economics

### No universal “cheap loop beats frontier one-shot” rule

The available evidence shows a Pareto frontier, not a single winner:

- Aider’s published leaderboard reports both success and cost, with large differences between configurations. [Aider leaderboard](https://aider.chat/docs/leaderboards/) — **Medium–High**.
- Cognition reports that a specialized smaller bug detector matched its frontier baseline in-distribution and ran roughly 10× faster, while remaining worse out-of-distribution. [SWE-Check](https://cognition.com/blog/swe-check-10x-faster) — **Medium**, vendor-reported.
- Cursor tested a more expensive summarization model and found negligible quality improvement relative to cost. [Cursor harness improvement](https://cursor.com/blog/continually-improving-agent-harness) — **High**.
- Anthropic found that upgrading the underlying model could outperform merely doubling an older model’s token budget. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system) — **High as a reported internal result**.

The defensible policy is: route to the cheapest configuration that clears a task-specific reliability threshold, and escalate on ambiguity, repeated failure, or high consequence. Routing itself must be evaluated on the real workload distribution, not chosen from model branding. [Mercor routing analysis](https://www.mercor.com/blog/mercor-model-routing-eval-problem/), [Cursor CursorBench](https://cursor.com/blog/cursorbench) — **Medium–High**.

### Measure cost per accepted outcome

Useful measures are:

- Cost per verified task.
- Cost per merged and retained change.
- Cost per deployed feature.
- Cost per repaired incident.
- Human minutes per accepted outcome.
- Rework and rollback rate.
- Token and tool-call breakdown by role and terminal state.

Cursor tracks latency, token efficiency, calls, cache hit rate, user satisfaction, and “Keep Rate”—whether generated code remains after fixed periods. Cognition explicitly reports that closing its review loop greatly increased token spend but reduced bugs. [Cursor harness improvement](https://cursor.com/blog/continually-improving-agent-harness), [Devin review loop](https://cognition.com/blog/closing-the-agent-loop-devin-autofixes-review-comments) — **High**.

Multi-agent work should have an explicit value threshold. Anthropic reports ordinary agents using about 4× chat tokens and multi-agent systems about 15×; its compiler experiment consumed two billion input tokens and almost $20,000. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system), [Parallel Claude compiler](https://www.anthropic.com/engineering/building-c-compiler) — **High**.

### Evaluating harness changes

The strongest practitioner pattern combines:

- Offline, versioned, representative tasks.
- Held-out or contamination-resistant cases.
- Online A/B tests on actual usage.
- Outcome metrics rather than activity metrics.
- Trace inspection and failure clustering.
- One-component ablations.
- Re-evaluation whenever the base model changes.

Cursor uses public benchmarks, a production-derived private suite, online A/B tests, Keep Rate, satisfaction signals, and ablations; it reports shelving ideas whose added cost did not improve user outcomes. [Cursor harness improvement](https://cursor.com/blog/continually-improving-agent-harness), [CursorBench](https://cursor.com/blog/cursorbench) — **High**.

Anthropic warns that harness assumptions become stale as models improve, and demonstrated removing context-reset machinery that a newer model no longer required. [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents), [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps) — **High**.

## 4. Known failure modes

| Failure | Evidence and mitigation | Confidence |
|---|---|---|
| Context rot and context anxiety | Tool errors and stale material contaminate later decisions; some models wrap up early near perceived context limits. Use selective retrieval, external history, structured handoffs, and sometimes fresh contexts. [Cursor harness improvement](https://cursor.com/blog/continually-improving-agent-harness), [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps) | **High** |
| One-shot overreach | Long-running agents try to build too much, exhaust context mid-feature, and leave undocumented partial state. Force incremental scopes and clean handoffs. [Anthropic long-running harness](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) | **High** |
| Under-provisioned environments | Missing dependencies, services, credentials, or verification access may cause subtle quality degradation rather than a clear crash. Treat the development environment as part of the product. [Cursor cloud-agent lessons](https://cursor.com/blog/cloud-agent-lessons) | **High** |
| Reward hacking and test tampering | Agents can modify evaluators, leak held-out data, or optimize reported scores rather than outcomes. Freeze or separately own evaluators and audit file access. [RewardHackingAgents](https://arxiv.org/abs/2603.11337) | **Medium–High** |
| Over-mocked or weak tests | A large empirical study found agent commits more likely to add mocks, which may validate isolated behavior while missing real integrations. Require integration and experiential checks. [Over-mocked tests study](https://arxiv.org/abs/2602.00409) | **Medium** |
| Sycophantic or lenient review | Anthropic reports agents praising mediocre self-produced work; even separate LLM evaluators remain inclined toward generosity. Calibrate skeptical evaluators and combine them with deterministic evidence. [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps) | **High** |
| Judge self-preference | Research reports model judges systematically favoring or disfavoring their own family’s outputs; structured multidimensional evaluation reduced but did not eliminate the issue. [Self-preference bias study](https://arxiv.org/abs/2604.22891) | **Medium** |
| Evaluator and benchmark overfitting | Flawed tests, gold-answer familiarity, and rigid graders can make measured progress fictitious. Use held-out tasks, production A/B tests, multiple signals, and regular refreshes. [OpenAI SWE-bench audit](https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/), [AI21 gold-like judge bias](https://www.ai21.com/blog/gold-like-answers-benchmarks/), [CursorBench](https://cursor.com/blog/cursorbench) | **High** |
| Runaway fan-out and spend | Anthropic observed leads spawning 50 subagents and searching endlessly; multi-agent token use was about 15× chat. Enforce fan-out, role, token, tool, and value budgets. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system) | **High** |
| Silent stalls and hanging work | Cursor warns that an unattended cloud agent can wait for permission for hours; Cognition has shipped fixes for stuck, crashing, and sleep/wake failures. Use durable waits, deadlines, heartbeats, and explicit blocked states. [Cursor cloud-agent lessons](https://cursor.com/blog/cloud-agent-lessons), [Devin stuck/hanging fixes](https://cognition.com/blog/dec-24-product-update-2) | **High** |
| Self-modification and trust-boundary collapse | Candidate-controlled prompts, tests, or architect output can become executable authority; an Aider issue demonstrates poisoned repository content propagating through architect/editor into committed malicious code. Separate credentials and authoritative evaluators from generated code. [Aider prompt-injection issue](https://github.com/aider-ai/aider/issues/5058), [Anthropic Managed Agents security boundary](https://www.anthropic.com/engineering/managed-agents) | **Medium–High** |
| Multi-agent incoherence | Workers duplicate effort, leave gaps, make incompatible implicit decisions, or overwhelm the lead with updates. Use bounded ownership, structured outputs, and independent work only. [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system), [Cognition multi-agent report](https://cognition.com/blog/multi-agents-working) | **High** |

## 5. What separates a toy loop from a production loop

A production loop has all of the following:

1. **A real execution environment**, not merely a shell and a model. [Cursor cloud-agent lessons](https://cursor.com/blog/cloud-agent-lessons)
2. **Durable workflow and event state** that survives agent, VM, and provider failure. [Cursor cloud-agent lessons](https://cursor.com/blog/cloud-agent-lessons), [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents)
3. **An external definition of done**, plus named failure and wait states. [Claude loops](https://claude.com/blog/getting-started-with-loops), [SWE-agent](https://swe-agent.com/latest/reference/agent/)
4. **An incumbent and bounded remediation**, so failed experiments do not corrupt the last good result. [autoresearch](https://github.com/karpathy/autoresearch/blob/master/program.md)
5. **Selective context plus recoverable memory**, not an ever-growing conversation or one lossy summary. [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents)
6. **Application legibility**—tests, browser state, logs, metrics, and traces available to the agent. [OpenAI harness engineering](https://openai.com/index/harness-engineering/)
7. **Security boundaries around generated code and credentials.** [Anthropic sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing), [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents)
8. **Cost, retry, timeout, and no-progress budgets.** [SWE-agent](https://swe-agent.com/latest/reference/agent/), [Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system)
9. **Harness evaluation against real usage**, including ablations and online signals. [Cursor harness improvement](https://cursor.com/blog/continually-improving-agent-harness)
10. **A real product and real users anchoring investment.** OpenAI explicitly credits actual use, deployment, breakage, and repair with keeping its harness work grounded. [OpenAI harness engineering](https://openai.com/index/harness-engineering/)

# Part B — Adversarial review against the one-man-plus-agents company goal

## 1. Evidence boundary

I used only the supplied material for claims about your system:

- **E1:** inlined VISION.
- **E2:** inlined `CLAUDE.md`.
- **E3:** inlined `AGENTS.md`.
- **E4:** prior gap review.
- **E5:** headers and decisions from PLAN-003 through PLAN-006.
- **E6:** outer-loop forensics.
- **E7:** dispatcher function surface.

I did not independently inspect implementation code. Where E4 says enforcement is evidence-limited, I retain that qualification.

## 2. Bottom-line judgment

Your architecture is a **high-assurance spec-to-PR subsystem**, not an AI engineering company.

It starts after most product judgment has happened and stops before customer value exists. The vision requires:

> idea → challenge → decision → product plan → tickets → execution → release → running service → operational feedback → maintenance

The evidenced implementation is concentrated around:

> approved spec → isolated attempt → integrity/scope/test/review → PR → integration

That middle segment is valuable, but it cannot serve as the top-level architecture. It should become one replaceable service inside a wider product-and-operations loop.

## 3. Load-bearing versus ceremony

| Keep—load-bearing | Judgment |
|---|---|
| Worker isolation and credential separation | Correct. Autonomous generated code must not inherit the operator’s home, tokens, or unrestricted network. E2/E3 identify both the D5 boundary and the residual copied-token risk. |
| Immutable, schema-validated intent and bounded scope | Correct for delegated implementation. Specs, allowed paths, digests, and clean attempts reduce silent reinterpretation. E2/E3. |
| Commit/base-bound verification and stale-base refusal | Correct. A verdict against one commit/base must not silently authorize another. E2. |
| Deterministic tests plus independent review | Correct in principle, especially for security- or trust-critical work. E2. The reported false PASS shows the implementation must become truthful before more layers are added. E4/E5. |
| Bounded remediation and explicit escalation | Correct. Low/default/high limits and repeated-finding termination are real circuit breakers. E2. |
| Reconcile, cancellation by unit/cgroup, durable launch records | Correct reliability primitives for the execution kernel. E2/E7. |
| Event-driven durable outer-loop state | Necessary for the vision. E6 correctly identifies usage reset, detached completion, and operator input as events rather than fixed timer ticks. PLAN-006 is only a plan, not an evidenced capability. |

| Cut or sharply reduce—ceremony | Judgment |
|---|---|
| Brief-caliber plan for every substantive request | Disproportionate. E2 demands a SETUP-BRIEF-depth artifact for every substantive task, then challenge, authorization, digest binding, deviation accounting, and ledger reconciliation. That is a control-plane development protocol masquerading as a universal work protocol. |
| Mandatory dual-vendor treatment of every durable recommendation | Appropriate for irreversible architecture or major product bets; excessive for ordinary prioritization, ticket refinement, and reversible product experiments. E2 applies it broadly enough to make management throughput depend on repeated model ceremony. |
| Multiple overlapping records of authority | Request ledger, plan, challenge, dispositions, authorization, spec, approval, attempt evidence, decision directory, escalation record, PR, and integration provenance create many opportunities for stale disagreement. E4 already reports inconsistent ledger/watchlist authority. |
| PLAN-004’s full observation-journal design before real product telemetry | Premature. Hash-linked generations, checkpoints, multiple implementation/schema/config/boundary digests, SQLite projection, static report, and twelve golden tasks optimize measurement provenance before the system has a deployed product or meaningful task distribution. E5. |
| PLAN-005’s elaborate break-glass token issuance | Normal operation should simply fail closed. A root-issued single-use token, scoped sudo policy, and root-owned redemption ledger are expensive machinery for an action explicitly described as full unisolated exposure. E5. Either prohibit it or keep a plainly manual operator-only emergency command outside autonomous operation. |
| Metrics extraction bundled into PLAN-003’s trust repair | The truthful required-test and verdict boundary is urgent; metrics refactoring is not part of the minimum security fix. E5 couples them. Split it out. |
| Permanent human-only `main` promotion for every change | Safe during bootstrap, but incompatible with autonomous routine maintenance at scale. E2 permanently forbids automated `main` promotion. Keep human approval for business releases and high-risk changes; permit policy-bound canary or maintenance releases after demonstrated reliability. |

There is also an internal policy collision. The strengthened planning rule says every substantive task requires a standalone plan artifact with no small-task exemption on depth; the later “Planning policy” says routine orchestrator actions require no separate plan documents or ceremony. E2 therefore does not provide one unambiguous intake rule. A management system with contradictory process authority will either stall or choose whichever rule justifies the current action.

## 4. Is the trust machinery worth it?

Partly.

The trust kernel is justified because the system executes untrusted generated code on a credentialed host. Isolation, external credentials, fixed authoritative tests, commit/base binding, and fail-closed review are not bureaucracy; they protect the operator and the product.

The sequencing and breadth are not justified:

- E4 reports no external tracker, deployment plane, service registry, product maintenance system, or representative end-to-end product.
- Meanwhile E5 contains four concurrent control-plane plans: installed-parent attestation, a cryptographically elaborate measurement journal, isolation break-glass, and persistent outer-loop supervision.
- E2 requires high-detail plans and validation even for much of the work required to simplify those mechanisms.

For a one-person company, the scarce resource is operator attention. Your current design spends that attention certifying that the factory followed its process. It does not yet measure whether the factory found a valuable problem, deployed a useful solution, retained users, or restored a failed service.

### Minimum trust kernel I would keep

1. Separate worker identity and inaccessible credentials.
2. Clean worktree/container per attempt.
3. Immutable task intent, allowed scope, and reviewed commit identity.
4. Parent- or CI-owned required tests that the candidate cannot alter for its own verdict.
5. Deterministic checks followed by independent review for moderate/high-risk work.
6. Protected release credentials and audit log.
7. Automatic rollback or stop on failed post-deploy health checks.

Everything else must justify itself through measured reduction in escaped defects, incidents, operator minutes, or loss exposure.

## 5. Architecturally missing capabilities

### Idea and product management

E1 requires arbitrary idea intake, grilling, decision-making, and decomposition. E2 defines a policy for dual research but E4 finds no repeatable intake workflow connecting an idea to a completed lifecycle.

Missing:

- An `Idea` object with hypotheses, target customer, problem, evidence, expected value, risks, and decision.
- A falsification workflow and explicit `reject`, `experiment`, or `build` result.
- Product success metrics and a kill criterion.
- A small-experiment path that does not require production-grade planning ceremony before uncertainty has been reduced.

### Ticket and portfolio management

E1 explicitly requires Jira or Linear. E4 finds no adapter, external IDs, idempotency, or drift reconciliation.

Missing:

- Dependency-aware work graph.
- Linear/Jira create/update/close synchronization.
- One authoritative mapping from product objective to ticket, spec, attempt, PR, release, and service.
- Priority and capacity decisions across multiple products, not merely per-spec dispatch order.

### Deployment and release

The current lifecycle ends at PR/integration. E4 reports no build artifact, environment, rollout, secret-reference, health-verification, or rollback abstraction.

Missing:

- Release object bound to a reviewed commit.
- Target adapters for the actual hosting environments.
- Build and artifact provenance.
- Environment configuration and secret references.
- Canary/staged rollout.
- Automated smoke and product-journey checks.
- Rollback and release evidence.

### Running and maintaining products

`dispatch health` monitors workers, not products. E4 finds no service inventory, SLOs, incidents, dependency upkeep, or autonomous maintenance.

Missing:

- Service registry: owner, repository, environment, endpoints, dependencies, SLO, runbook, deploy and rollback actions.
- Telemetry ingestion: errors, latency, availability, business events, cost.
- Alert → incident → diagnosis → ticket → fix → release → verification loop.
- Scheduled security, dependency, certificate, backup, and data-integrity work.
- Maintenance budgets and escalation rules.

### Cross-run memory

The request ledger and repository plans are process memory, not a complete organizational memory.

Missing:

- Durable event/state store spanning idea, product, engineering, release, and operation.
- Retrieval by lifecycle identity rather than by manually navigating directories.
- Product decisions, experiment results, user feedback, incidents, and postmortems.
- Reconciliation rules for duplicated or contradictory state.

PLAN-006’s append-only controller state is directionally useful, but its persistent Claude-in-tmux design couples liveness to a UI process. The stronger shape is an ephemeral reasoning process over a durable session/workflow log, as demonstrated by Cursor and Anthropic in Part A.

### Cost and economic control

E2 discusses quota interruption but not business-level economics.

Missing:

- Per-product, per-idea, per-ticket, per-attempt, and per-month budgets.
- Forecast and authorization before expensive multi-agent or long-running work.
- Cost per accepted ticket, deployed feature, incident repair, and active user.
- Model routing by evaluated task class.
- Automatic stop or downgrade on poor marginal progress.
- Separation of usage exhaustion from business-budget exhaustion.

### Product feedback

This is the most important omission. There is no evidenced loop from deployed behavior or customer response back into prioritization.

Without product telemetry, customer reports, support intake, adoption, retention, and business outcomes, the system’s objective function becomes “produce approved artifacts and green PRs.” That is not the operator’s goal.

## 6. Biggest structural risk

The biggest risk is not a security breach. It is **process becoming the incumbent product**.

The evidence already shows:

- Four control-plane plans in flight. E5.
- A mandatory plan, challenge, authorization, and ledger process for virtually every substantive action. E2.
- Known inconsistency inside the authority records. E4.
- No representative idea-to-running-product pilot. E4.
- No external ticketing, deployment, or real maintenance loop. E4.
- An outer loop whose previous version consumed overnight time without validated progress. E6.

This creates a recursive trap:

1. Add a control mechanism.
2. Discover that the mechanism itself needs a trust boundary.
3. Create a plan and dual review for that boundary.
4. Add evidence and metrics for the review.
5. Discover that the evidence system needs activation and integrity rules.
6. Repeat without shipping the product that would reveal which controls matter.

A perfectly governed PR factory can still produce zero customer value. Worse, green gates can create false confidence because they validate conformance to a spec, not whether the spec describes a valuable product.

## 7. The architecture that better fits the goal

The existing dispatcher should survive, but as the **engineering execution service**, not the system’s center.

```text
Idea inbox
   ↓
Research / falsification / operator decision
   ↓
Product goal + measurable outcome + budget
   ↓
Work graph ↔ Linear/Jira
   ↓
Existing spec-to-PR execution kernel
   ↓
Build artifact → staged release → health verification
   ↓
Running service registry
   ↓
Telemetry + users + support + incidents + costs
   └──────────────→ reprioritized goals and maintenance tickets
```

### A. Durable manager loop

Use a durable workflow controller with a small explicit state machine. A model process should be replaceable:

1. An event arrives: operator input, research completion, ticket state, attempt completion, CI, deployment, alert, schedule, or budget reset.
2. The controller loads the affected lifecycle object.
3. A bounded manager episode receives only relevant state and available typed actions.
4. The episode proposes or performs authorized actions.
5. The controller validates state change, records costs and evidence, and schedules the next event.
6. No progress, repeated failure, missing authority, or exhausted budget produces a terminal state and operator notification.

Do not make a tmux-held Claude process the durable brain. Persist the session and workflow; restart the reasoning process freely.

### B. One lifecycle spine

Create one minimal authoritative model:

- `Idea`
- `Decision`
- `ProductGoal`
- `Ticket`
- `Attempt`
- `Change`
- `Release`
- `Service`
- `Signal`
- `Incident`
- `MaintenanceTask`

Each entity needs an ID, status, parent links, decision authority, budget, and current next action. Git remains authoritative for code; a transactional store should own operational state; large raw evidence can live in object storage with digests.

Do not begin with PLAN-004’s full cryptographic observation journal. Begin with enough transactional integrity to recover, reconcile, and answer “what is the next action?”

### C. Risk-scaled autonomy

- **Low risk:** routine dependency bumps, bounded fixes, documentation, reversible maintenance → automatic execution, CI, canary, health check, rollback.
- **Moderate risk:** features and multi-component fixes → independent review and operator-visible release summary; automated release if project policy permits.
- **High risk:** credentials, data migration, security boundary, irreversible external effects → human authorization and stronger independent validation.
- **Business decisions:** operator approves product bets, budgets, shutdowns, and major scope changes.

Planning depth should scale with uncertainty, reversibility, and blast radius—not merely whether a task is “substantive.”

### D. Product-level validators

Every product goal needs at least one validator above code tests:

- A user journey that succeeds.
- A measurable latency, reliability, or quality threshold.
- Adoption or retention evidence.
- A customer-confirmed resolution.
- A bounded experiment outcome.
- A health/SLO improvement.

A feature that passes tests but does not improve its product metric should not become a successful incumbent.

### E. Economic governor

Before each episode or fan-out:

- Estimate maximum spend.
- Check remaining product and monthly budgets.
- Choose the cheapest evaluated model/harness for the task class.
- Reserve frontier models for ambiguity, architecture, and repeated failures.
- Stop when marginal verified progress no longer justifies cost.
- Report cost per shipped and retained outcome.

## 8. What to do with the four plans

1. **PLAN-005 — execute the fail-closed core, but delete normal break-glass complexity.** Isolation unavailable should mean no autonomous dispatch. Preserve only an unmistakably manual emergency mechanism if the operator truly needs one.
2. **PLAN-003 — trim again.** Deliver parent/CI-owned required tests, truthful assertion execution, candidate/commit/base binding, and fail-closed verdict handling. Remove metrics refactoring and anything not necessary to prevent false certification.
3. **PLAN-006 — keep the durable controller, discard the persistent-tmux brain assumption.** Implement recoverable workflow state, event delivery, explicit waits, progress validation, budgets, and circuit breakers with restartable agent episodes.
4. **PLAN-004 — defer the elaborate journal.** Start with a minimal cost/outcome dashboard and a small representative evaluation set derived from the first real product. Expand only when observed failures demand it.

## 9. Recommended sequence

1. Freeze new general control-plane mechanisms.
2. Close the known false-PASS and isolation fail-open paths with the smallest truthful kernel.
3. Select one real product and define one customer-visible outcome.
4. Build minimal idea intake and a Linear/Jira work graph for that product.
5. Use the current dispatcher for implementation.
6. Add one deployment target, canary, health check, and rollback.
7. Add service monitoring and one automated incident-to-ticket loop.
8. Implement the durable outer workflow around those real lifecycle events.
9. Run one maintenance event after deployment.
10. Measure operator minutes, total cost, escaped defects, release frequency, rollback rate, and product outcome.
11. Permit no new control-plane abstraction unless that pilot exposes the need.

The system should earn architectural generality by shipping and maintaining one product. Until then, the safest assumption is that every new universal mechanism may be solving the factory’s internal anxieties rather than the operator’s actual problem.

# Final verdict

The current approach is not fundamentally worthless; it is fundamentally **mis-centered**.

Keep the isolated, bounded, evidence-based execution kernel. Stop treating it as the company. Build the lifecycle around customer and operational events, make agents restartable over durable state, scale ceremony by risk, and force the next milestone to be a real idea that reaches a running service and then generates a maintenance event.

If that vertical slice is postponed again in favor of further trust, measurement, or authorization machinery, the architecture will be demonstrating the exact failure mode it was designed to prevent: a sophisticated loop making no progress toward the real objective.

RESEARCH COMPLETE
