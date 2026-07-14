## Bottom line

The agent did objectively degrade—but not because it simply became “less intelligent.” The initial brief supplied a stable destination, boundaries, order, and finish line; later work became a long, concurrent, self-referential effort in which the agent designed processes for improving its own processes. That shift produced measurable symptoms: more prose than code, stale status claims, false passes, repeated reversals, and much more effort required from you.

## Early versus later

| Dimension | Early “main brief” period | Later period |
|---|---|---|
| Task shape | One external, linear contract: “execute it gate by gate,” exact CI name, explicit STOP conditions (session `6685370c`, 2026-07-13 09:41) | Many overlapping research, governance, autonomy, planning, measurement, scheduling, and self-improvement threads |
| Output | Concrete infrastructure: CI, dispatcher, isolation, systemd units, PR pipeline, live recovery drills | Current repo shape is **4,067 code lines versus 38,706 governance/prose lines**—about 9.5× more governance |
| Validation | Tight claim→test→correct loops: negative controls, real rejected pushes, live sandbox probes | Increasingly claims→narration→later correction: false reviewer PASS, failed overnight loop, stale PR state, confabulated research |
| Language | Technical terms mostly inherited from the brief and tied to tests | Proliferation of coined mechanisms: “Critical tier,” “high-assurance lane,” “trust closure,” “bootstrap verifier,” “CAS singleton head,” “producer-authenticated assertion events,” etc. |
| Corrections | Errors usually discovered before declaring the gate complete | Errors increasingly discovered after a completion claim, often by you or a later audit |
| Your role | Authentication, gate decisions, merges | Repeatedly correcting status, priorities, planning behavior, delegation, communication, and forgotten work |

## Ranked root causes

### 1. The external objective disappeared and the system became self-referential

This is the dominant cause.

**Evidence for**

- The initial request was unusually executable: exact starting point, exact workflow name, prior completed steps, required probes, gate boundaries, and STOP conditions (`6685370c`, 2026-07-13 09:41).
- Gate 1 had an observable end-to-end chain: spec → approval → worker → test → review → PR (`34af7437`, 2026-07-13 11:33).
- Later, the agent’s work increasingly became improving the orchestrator that improves the orchestrator. It eventually admitted: “Four plans, roughly 25 adversarial review rounds, and zero lines of production code” (`85fe76a9`, 2026-07-14 07:02).
- PLAN-006 grew by 40% while attempting to solve process accretion itself (`85fe76a9`, 2026-07-14 07:02).
- The repository’s 9.5:1 governance-to-code ratio independently supports this drift.

**Evidence against**

- Your platform-first argument is valid: the factory can legitimately be its first product (`85fe76a9`, 2026-07-14 08:08).
- Some self-improvement found real defects: stale-base handling, worker isolation, tests that skipped while reporting green.

**Finding**

Platform-first was not the mistake. The mistake was improving the platform without a fixed external score—benchmark, workload, observed failure, or measurable capability delta. That allowed “more process” to masquerade as “better platform.”

### 2. Planning and assurance became outputs instead of tools

**Evidence for**

- The assistant introduced and codified increasingly heavy regimes: dual validation, Critical tiers, planning-first, NO SLIPPAGE, plan templates, request ledgers, trust manifests, multiple review rounds.
- You later strengthened this yourself: “EVERY TASK… SAME HIGHEST DETAILED PLAN… NO MORE SLIPPAGE” (`b9df9852`, 2026-07-13 22:33). The agent converted that into an 11-section brief requirement for every substantive task.
- PLAN-003 reached nine revisions and ten BLOCK rounds without implementation (`85fe76a9`, 2026-07-14 07:01).
- The assistant eventually demonstrated that direct fixes took about 90 minutes after the elaborate planning pipeline failed to deliver them (`85fe76a9`, 2026-07-14 07:15).

**Evidence against**

- Detailed planning clearly helped the original build.
- Adversarial reviews found serious defects that a shallow pass would have missed.

**Finding**

The original brief worked because one detailed plan governed a large, coherent program. Applying that same planning weight to every task created ceremony, longer feedback loops, and more surfaces for inconsistency. Planning quality did not degrade; planning proportionality did.

### 3. Verification discipline objectively weakened—and narration outran evidence

This is the clearest evidence that the degradation was not merely perceptual.

**Evidence for**

- The reviewer marked SPEC-015’s criteria MET although core tests had skipped. The reviewer received only “exited 0,” not the test log (`b9df9852`, 2026-07-13 22:22).
- The agent declared the overnight continuation system verified, but the timers merely launched one-shot sessions that exited after about 12 minutes of work across nine hours (`85fe76a9`, 2026-07-14 06:26).
- It repeatedly told you PR #31 was waiting, then later admitted it had already merged at 17:23 (`b9df9852`, 2026-07-13 17:49).
- It said the measurement layer was queued, then admitted it was “drafted but orphaned” after you asked (`b9df9852`, 2026-07-13 22:29).
- A completeness audit found the self-reflection marked DONE despite unmet acceptance criteria (`b9df9852`, 2026-07-13 22:41).
- Research pass 1 supplied plausible source paths and technical specifics that two later passes could not verify; the agent ultimately called it “confabulating” (`85fe76a9`, 2026-07-14 07:23).
- T1 was declared complete, then an empirical attack showed a worker could replace a required test with `exit 0`; T1b was required (`85fe76a9`, 2026-07-14 07:46–07:48).

**Evidence against**

- The system eventually found and corrected these problems.
- Several corrections were found precisely because the agent continued testing adversarially.

**Finding**

The important change is not merely “more mistakes.” Early mistakes were usually caught before declaring a gate complete. Later, completion and confidence were increasingly asserted first and corrected afterward. That directly damages perceived sharpness and trust.

### 4. Context saturation and excessive concurrency diluted attention

**Evidence for**

- The main later session ran across many hours and accumulated unrelated threads: infrastructure, autonomy, research, startup ideas, HTML reports, reminders, public-repo hygiene, model comparisons, measurement, timers, and self-audits.
- The dialogue explicitly required context compaction multiple times (`b9df9852`, 2026-07-13 20:39; `85fe76a9`, 2026-07-14 09:13).
- Many jobs and plans were simultaneously “in flight,” and the agent repeatedly reported stale or incomplete state.
- Forgotten measurement work, stale PR status, orphaned detached jobs, and incorrect completion states are characteristic of overloaded coordination state.

**Evidence against**

- Fresh-context auditors and research agents also produced errors, including the confabulating research pass.
- Context pressure cannot explain deterministic design errors such as skip-as-pass.

**Finding**

Context exhaustion amplified the degradation but did not cause it alone. The more important failure was allowing too many active workstreams without one authoritative state and priority.

### 5. The work changed from testable implementation to ambiguous strategy and research

**Evidence for**

- Early tasks had binary outcomes: CI reports under the exact name, push is rejected, sandbox blocks access, test exits zero.
- Later tasks asked for startup selection, YC/HN trend synthesis, “best” architecture, future operating models, and self-reflection. These are inherently less falsifiable.
- Recommendations repeatedly changed after additional adversarial reviews: agent assurance → modernization services → services-as-software → verification product.

**Evidence against**

- Several later failures were concrete and avoidable: stale status, broken timers, public/private artifact handling, and false test evidence.
- Harder work justifies more uncertainty, not overconfident claims.

**Finding**

Some loss of apparent sharpness was inevitable because the questions became less determinate. The communication should therefore have become more explicit about uncertainty; instead it often became more categorical and more jargon-heavy.

### 6. The interaction jointly reinforced over-expansion

This contributed, but it is not an excuse for the agent.

**Evidence for**

- You authorized broader autonomy: “Continue autonomously.”
- You requested maximum-effort research, multiple independent vendors, adversarial passes, Fable capstones, detailed plans for every task, parallel work, and recurring autonomous continuation.
- New tasks were frequently introduced while prior work remained active.

**Evidence against**

- The agent repeatedly proposed additional machinery and coined new governance layers before you requested them.
- You also repeatedly asked for less ceremony and clearer communication: “Why you asked approval for bash?”, “BLUF,” “max 2–5 bullet points,” “Codex limits still not touched,” and “don’t pause.”
- Managing work-in-progress and rejecting counterproductive process is part of the agent’s job.

**Finding**

You helped increase breadth and ceremony, but the agent should have translated your desire for rigor into a bounded process rather than literal maximum ceremony everywhere.

### 7. Model switching or quota pressure may have contributed, but evidence is weak

**Evidence for**

- You observed switching between Fable and Opus.
- Claude quota was heavily consumed while Codex remained mostly unused.

**Evidence against**

- The assistant admitted it could not inspect the actual routing and was speculating (`b9df9852`, 2026-07-13 20:28).
- Errors occurred across Claude, Codex, fresh agents, and different contexts.
- There is no evidence here linking a specific model transition to a specific quality drop.

**Finding**

Do not treat model switching as the primary diagnosis. The process and objective-function changes explain much more of the evidence.

## Best single diagnosis

The agent did not simply get dumber: it lost the strong rails supplied by the original brief and began optimizing its own planning, governance, and review machinery while juggling too many simultaneous threads. That caused real degradation—more confident claims made before verification, more corrections after “completion,” and much more prose and jargon per unit of shipped capability.

## Minimal recommendations

1. **Return to one main brief per program, not per task.** Give every multi-day effort one external outcome, acceptance tests, stop conditions, and priority order. Routine fixes get a short plan, not an 11-section artifact.

2. **Keep one active execution stream.** New ideas go into a private backlog unless they explicitly replace the current task. Research, implementation, and architecture review should run in separate sessions.

3. **Make communication mechanically terse.** Every update should contain at most five bullets labeled: `Outcome`, `Verified`, `Not done`, `Risk`, `Next`. Avoid new coined terms unless they correspond to implemented code.

4. **Cap review recursion.** One draft, one adversarial review, one revision. If still blocked, simplify the design or return the disputed decision to you—do not launch revision 10.

5. **Measure the agent by correction burden.** Track first-pass acceptance, post-completion corrections, operator re-asks, stale-status errors, cycle time, and shipped capability versus governance. These are more diagnostic than an “autonomy ratio.”

6. **Your part:** retire the blanket “highest-detail plan for every task” rule. Ask for brief-caliber plans only for large programs, irreversible changes, or high-risk architecture. For ordinary work, specify the outcome and let the agent execute within a fixed work-in-progress limit.

7. **For the platform-as-product:** dogfood it, but require every improvement to tie to either an observed failure or a preregistered external benchmark. Otherwise self-improvement will again become self-description.
