## Retrieval verdict

The substantive design was recovered, but not as a complete verbatim X thread.

- The [original X status](https://x.com/0xCodila/status/2072329149520232639) returned empty HTML.
- [XCancel](https://xcancel.com/0xCodila/status/2072329149520232639) and [Nitter](https://nitter.net/0xCodila/status/2072329149520232639) could not be fetched in this environment.
- A contemporaneous Chinese article identifies Codila, cites the exact status ID, and reproduces the loop mechanics in detail. This is the main recovery source—not a claim that its prose is verbatim thread text. [AI Frontline reproduction](https://news.marsbit.co/20260706202809896370.html)
- A podcast episode independently associates the exact status ID with “Agent Loop,” Karpathy’s method, metrics, limits, and an exit rule. It corroborates the subject, but not all implementation details. [No Tiene Nombre episode](https://open.spotify.com/episode/33X8YjgSDseu5FCNnIE20E)
- The recovered mechanics align closely with the linked primary implementation: [Karpathy/autoresearch](https://github.com/karpathy/autoresearch) and its operative [`program.md`](https://github.com/karpathy/autoresearch/blob/master/program.md).
- No separate Codila blog or repository containing the thread was found.

Confidence: high for the core loop; medium for Codila’s exact ordering/wording; low for any claim that the entire original thread was recovered verbatim.

## Faithful reconstruction

### Control flow

1. A human writes or maintains a standing instruction document defining exploration directions, constraints, and the objective.
2. Establish a baseline before experimentation.
3. Restrict the agent to a narrow mutation surface. In AutoResearch, it may edit `train.py`, while data preparation and evaluation in `prepare.py` are off-limits.
4. For each iteration:

   `inspect incumbent → propose one change → commit candidate → run fixed experiment → extract metric → record outcome`

5. If the objective metric improves, advance the incumbent branch. If it does not, discard/reset the candidate. Crashes may receive a few repair attempts before being abandoned.
6. Repeat until a stopping condition is met. Codila’s generalization calls for target/max-round stopping; Karpathy’s concrete instruction instead runs until human interruption, while bounding each experiment and killing an individual experiment that runs excessively long. [AutoResearch operative loop](https://github.com/karpathy/autoresearch/blob/master/program.md)

This is an elitist “winner ratchet”: one accepted incumbent, one challenger, and no regression allowed on the primary metric.

### Roles

- **Human/operator:** defines the objective and constraints, approves setup, provides missing data, edits the standing instructions, eventually stops the run, and reviews the accumulated results.
- **Generator/optimizer agent:** proposes and implements experiments, diagnoses simple failures, and selects new directions.
- **Validator:** a fixed metric/evaluation path that the generator is not supposed to modify.
- **State carrier:** Git branch/commits plus an experiment ledger.
- **Optional meta-optimizer:** in the bilevel extension, an outer agent examines the search trace and changes how the inner loop searches.

Codila’s recovered formulation does not require a separate semantic-review agent. “Independent verification” primarily means a validator the generator cannot redefine.

### Gating

There are four distinct gates:

- **Scope gate:** only the designated mutation surface may change.
- **Execution gate:** the candidate must run successfully inside the experiment budget.
- **Metric gate:** accept only an objective improvement.
- **Complexity gate:** all else equal, prefer simpler code; small metric gains may be rejected if they buy excessive complexity.

The metric gate is strong and mechanical. The complexity gate is weak because the generating agent exercises the judgment itself. [AutoResearch constraints and acceptance policy](https://github.com/karpathy/autoresearch/blob/master/program.md)

Codila identifies three indispensable loop facilities:

- a real validator;
- durable state;
- a stopping condition.

The recovered applicability test is also important: use a loop only when the task repeats frequently, verification can be automated, retry cost is affordable, and the agent has access to the real execution environment. [Exact-status reproduction](https://news.marsbit.co/20260706202809896370.html)

### Memory and state

Karpathy’s concrete state model is:

- `program.md`: durable policy and constraints;
- current branch/commit: best accepted solution;
- `results.tsv`: experiment, metric, memory use, outcome, and description;
- `run.log`: detailed execution/failure evidence;
- Git history: accepted changes.

The notable defect is that `results.tsv` is deliberately untracked, making the most important search history less durable and less auditable than the accepted code.

### Review and verification

- Objective verification is deterministic and separated from the editable file.
- Failed candidates are reverted rather than allowed to contaminate the incumbent.
- There is no PR review, security review, semantic requirements review, or independent human-equivalent reviewer inside the loop.
- The same agent still chooses hypotheses, implements them, interprets crashes, and judges qualitative complexity.

The bilevel variant adds trace analysis and mechanism generation: an outer loop inspects failures such as repetitive proposals, creates a new search mechanism, validates that it loads, and reverts it on failure. Its paper also reports serious limitations: silent fallback bugs, dependency exposure, evaluator overfitting, and no stability guarantee. [Bilevel Autoresearch paper](https://arxiv.org/abs/2603.23420)

### Human touchpoints

Humans:

- choose the run identifier and objective;
- confirm setup;
- provision data/environment when necessary;
- author the standing instructions;
- manually interrupt the concrete AutoResearch loop;
- inspect the ledger and accepted branch afterward.

They do not approve every iteration.

## Comparison with our orchestrator

Repository caveat: the supplied AGENTS.md was available in the prompt, but local reads of [CLAUDE.md](/home/val/orchestrator/CLAUDE.md), [dispatch.py](/home/val/orchestrator/scripts/dispatch.py), [PLAN-003.md](/home/val/orchestrator/.orchestrator/plans/PLAN-003.md), and [PLAN-004.md](/home/val/orchestrator/.orchestrator/plans/PLAN-004.md) failed before execution because the read-only sandbox could not initialize (`bwrap: loopback: Failed RTM_NEWADDR`). Therefore the comparison below is against the declared architecture in the supplied AGENTS.md, not a code-verified audit of those files.

| Dimension | Codila/AutoResearch | Our declared design | Assessment |
|---|---|---|---|
| Input authority | Mutable instruction document | Schema-validated, digest-approved, immutable spec | Ours stronger |
| Mutation scope | One editable file by instruction | Declared scope gate plus isolated worktree | Ours broader and stronger, but their frozen evaluator boundary is exceptionally clear |
| Iteration | Continuous improve/evaluate/retain loop | Discrete worker attempts through gates | Their feedback loop is stronger |
| Verification | One scalar metric plus subjective simplicity | Integrity → scope → test → bounded review | Ours substantially stronger for software correctness |
| Isolation | Branch boundary | Dedicated UID, hardened system service, protected operator home, separate worktree | Ours substantially stronger |
| State | Branch, untracked TSV, raw log | Per-attempt evidence, tracked manifests, hashes | Ours stronger for auditability |
| Search memory | Explicit record of successful and failed hypotheses | Attempt evidence, but no declared cross-attempt hypothesis/outcome learning model | Theirs stronger semantically |
| Acceptance | Automatic monotonic ratchet | Gate pass produces a reviewable PR | Different goals; ours is safer, theirs learns faster |
| Human control | Setup and eventual interruption | Approval artifacts, PR review, integration branch, operator-only promotion | Ours much stronger |
| Stop policy | Generalized target/max rounds; concrete implementation runs until interrupted | Not established from readable evidence | Their general rule is worth adopting |
| Evaluator tampering | Explicitly forbidden | Integrity/scope checks detect changes after the fact | Potential advantage to theirs if immutability is technically enforced |
| Evidence of rejected work | TSV entry, but untracked | Hashed attempt evidence | Ours stronger structurally; theirs records better experiment semantics |

The important distinction is that AutoResearch optimizes a scalar benchmark, while our orchestrator produces general software changes whose correctness cannot usually be collapsed into one number. Copying its automatic “metric improved, therefore accept” rule would weaken our governance.

## Ranked reuse candidates

Because PLAN-003/004 could not be read, I will not invent their ownership. Each candidate therefore identifies the exact subsystem/spec surface and gives a provisional plan placement requiring confirmation.

1. **Semantic attempt ledger — highest value**

   Record for every attempt: parent/incumbent, hypothesis, intended mechanism, changed scope, gate outcomes, failure class, keep/discard decision, and next suggested direction. Make it append-only or hash-bound; do not emulate the untracked TSV.

   - Effort: **Medium, 2–4 days**
   - Slot: attempt evidence/manifest work under `.orchestrator/attempts`; whichever of PLAN-003/004 owns persistence and retry orchestration
   - Value: prevents rediscovery of failed approaches and turns evidence into usable cross-attempt memory.

2. **Gate-informed retry loop with an explicit incumbent**

   After a failed worker attempt, feed structured gate evidence into the next attempt. Preserve the last fully gated incumbent; rejected candidates never become the new base. Bound attempts by count/cost, not a short minute timeout—consistent with the repository rule that SOL consultations may legitimately take hours.

   - Effort: **Large, 1–2 weeks**
   - Slot: `scripts/dispatch.py` attempt lifecycle; provisional PLAN-004 if it owns multi-attempt execution
   - Constraint: acceptance still requires every existing gate, not merely improved tests.

3. **Technically immutable verifier boundary**

   Move approved specs, gate programs, and any acceptance fixtures outside the worker-writable mount or expose them read-only. Post-hoc scope detection remains valuable, but prevention is stronger than discovering evaluator tampering later.

   - Effort: **Medium–Large, 3–7 days**
   - Slot: existing D5 worker-isolation work and `tests/worker_isolation.sh`; provisional PLAN-003 if it owns isolation/integrity
   - Value: directly reuses AutoResearch’s best structural idea without adopting its weaker review model.

4. **Loop-eligibility fields in the spec schema**

   Add an opt-in contract such as: objective verifier, repeatability, maximum attempts, cost ceiling, incumbent-selection rule, and required real-environment capabilities. Reject loop mode when no independent verifier exists.

   - Effort: **Small–Medium, 1–3 days**
   - Slot: `specs/spec.schema.json` plus dispatcher validation; whichever plan owns spec/runtime contracts
   - Value: prevents “agent hamster wheel” jobs from entering autonomous retry mode.

5. **Explicit stopping and circuit-breaker policy**

   Stop on success, exhausted attempt/cost budget, repeated identical failure class, lack of admissible new hypotheses, operator cancellation, or compromised validator integrity. Preserve the existing prohibition on minute-scale SOL timeouts.

   - Effort: **Medium, 2–4 days**
   - Slot: dispatcher attempt state and evidence manifests; likely alongside candidate 2
   - Value: Codila’s general formulation is stronger here than Karpathy’s literal “loop forever.”

6. **Offline harness/meta-loop experiments — defer**

   Use a frozen held-out corpus to propose improvements to prompts, schemas, gate ordering, or review rubrics. Never let the outer loop modify production gates at runtime; produce a normal reviewed spec/PR instead.

   - Effort: **Large/XL, 2–4 weeks**
   - Slot: a new post-PLAN-004 experiment plan, not the live dispatcher
   - Reason to defer: the bilevel paper itself documents silent fallback and unsafe self-modification risks. Its mechanism-search idea is interesting; runtime gate mutation is inappropriate for this orchestrator.

Bottom line: reuse the experiment ledger, incumbent ratchet, enforced verifier immutability, eligibility test, and stopping policy. Do not reuse scalar-metric acceptance, untracked state, self-graded qualitative review, destructive resets, or runtime self-modification of gates.

REVIEW COMPLETE
