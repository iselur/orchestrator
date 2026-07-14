# Claude challenge — PLAN-004 (Phase 2: measurement layer), revision of 2026-07-14T05:51:42Z

Reviewer: Claude (orchestrator). Verdict: **REVISE** — the architecture conformance, requirement
numbering, spec decomposition, SQLite/report/golden/matrix design are strong and preserve every
fixed decision from the accepted draft. But the plan's core section is built on a fabricated
evidence model, which is the exact "plan built on sand" failure the template warns about. Two
blocking objections, one clerical, two non-blocking.

## P1 (BLOCKING) — §4.3 "Exact extraction rules" invent the evidence schema

The plan presents mandatory JSON Pointers as "Phase-1-canonical fields." I verified the real
artifacts on this host (`.orchestrator/attempts/SPEC-015/1/`):

- **`result.json`** actual keys: `attempt, attempt_id, base_sha, commit_policy, error_class,
  finished, isolation, merged, merged_via, pr_url, reviewer_model, spec_digest, spec_id, status,
  test_command, worker_commit, worker_model`. The plan's `/terminal_status`, `/started_at`,
  `/duration_ms`, `/gates/*/status`, `/remediation/count`, `/escalation/path`, `/merge/*` — **none
  exist**, and Phase 1 (PLAN-003) does not create them: it adds a test-attestation artifact and
  changes the verdict schema; it does not restructure `result.json`.
- **`launch.json`** actual keys include `created, base_sha, base_branch, worker_model,
  worker_effort, reviewer_model, reviewer_effort, isolation, hard_ceiling_hours, worktree,
  approved_scope, spec_digest…`. The plan's `/started_at`, `/base_commit`, `/config_id`,
  `/harness_version`, `/model`, `/reasoning_effort`, `/isolation_mode`, `/allowed_paths` do not
  exist under those names; `config_id` and `harness_version` are not recorded anywhere today.
- **`review.json` v3** actual shape: `verdict, criteria[], scope_finding, regression_finding,
  security_findings, reasons[], spec_digest, base_sha, worker_commit, schema_version` (string "3")
  — per scripts/verdict.schema.json. The plan's `/final_verdict`, `/rounds/*/round`,
  `/rounds/*/findings/*` are **entirely fictional**; there are no review rounds or structured
  finding objects in v3.
- Codex `raw/events.jsonl`: the token paths ARE correct (`/usage/input_tokens`,
  `/usage/cached_input_tokens`, `/usage/output_tokens`, `/usage/reasoning_output_tokens` on
  `turn.completed`) — verified. But `/item/tool`, `/item/exit_code`, and `/duration_ms` on
  `turn.completed` are unverified; item records carry `type` (`command_execution`, `file_change`,
  `agent_message`, `todo_list`…) and the plan must derive tool identity from the real item shape.

Because §4.3 declares missing mandatory pointers `measurement_error` and §2.2 forbids heuristic
aliasing, this collector as specified would emit `measurement_error` for **100% of real attempts**
— fail-closed applied to a fantasy schema measures nothing. The §4.4 examples, §4.6 fact tables
(`gate_result`, `review_round`, parts of `attempt_fact`), and requirement 11's dependence on §4.3
inherit the defect.

Required disposition: re-derive §4.3/§4.4/§4.6 from the REAL artifacts (cite one concrete attempt
per source, as the drafting prompt required), plus PLAN-003's actual outputs (attestation JSON,
verdict v4 with `criteria[]` + structured `scope_findings`/`regression_findings`/`security_findings`
arrays). Fields the harness genuinely does not record (gate timings, per-attempt remediation
counts, config_id, harness_version, per-gate status objects) must be explicitly `null`-with-coverage
or derived (e.g. duration from `created`→`finished`; gate outcomes derivable from `status`/
`error_class` classes and evidence file presence) — never invented as mandatory. Where a field is
genuinely desirable but unrecorded, list it as a candidate for the four capture points or as
explicitly out of scope; do not pretend it exists.

## P2 (BLOCKING) — the collector cannot ingest what Phase 1 actually produces

§4.3 hard-requires `/schema_version == 3` for reviews. PLAN-003 Dispatch 5 moves all new reviews to
**v4** (one criteria entry per acceptance criterion with `criterion_index`; findings as structured
arrays with `advisory|blocker` severity). Phase 2 launches immediately after Phase 1 lands, so the
dominant review artifact will be v4 — under this plan every one becomes `measurement_error` or is
silently uncollected. Add `review_v4` extraction as the primary review event (it is also the
RICHER source: structured findings feed `finding` rows directly), with v1–v3 as display-only
historical epochs. Note the overlap: v4 structured findings partially duplicate the
`finding_disposition` capture point — reconcile (v4 = reviewer-asserted; disposition = operator
adjudication; keep both, linked by finding identity).

## P3 (clerical, BLOCKING for digest binding) — identity mismatch

Body title says `PLAN-PHASE-2` with a pseudo-metadata blockquote (ID `PLAN-PHASE-2`); the YAML
frontmatter says PLAN-004. Same defect class as PLAN-003's O1. Fix body identity to PLAN-004, drop
the pseudo-metadata line, and carry `ledger_ref: R19/R11`, `lane`, `supersedes` in the YAML
frontmatter only.

## P4 — P2-03's "outside dispatch" wrapper has an unstated dispatch dependency

Reviewer `claude -p` invocations live inside `scripts/dispatch.py` `review()` (dispatch.py:1195+).
A `scripts/claude-capture` wrapper only observes them if the call site is rewired — which edits
`dispatch.py`, i.e. P2-02's territory. Make the dependency explicit: P2-02 (high-assurance) owns
the call-site change (invoke-through-wrapper or emit-envelope-locally), P2-03 depends on P2-02, and
P2-03's "do not edit scripts/dispatch.py" stays true only under that ordering.

## P5 — terminal-only discovery silently drops known evidence classes

Discovery keys on `result.json` existence. Real corpus already contains attempts without terminal
results (SPEC-002/2 launch+interrupted with no result; orphan branches under audit reconciliation).
These become invisible rather than measured-as-incomplete. Add a coverage event (count + attempt
path + state-file class, no payload extraction) for attempt directories lacking `result.json`, so
the report's coverage view reflects them without touching non-terminal evidence.

## Minor (note, no disposition required)

- `reasoning_output_tokens` (real name) vs the plan's alternate-path handling — already correct.
- Requirement 15's byte-identical rebuild + `--as-of` design is good; keep.
- The golden manifest's shared reviewer-value block (tasks 07/08/10/11) satisfies the build-once
  constraint cleanly.

## Process note

After disposition, revised PLAN-004 gets the same treatment as PLAN-003: fresh-context SOL
adversarial critique of the identical revision, then Claude authorization. P2-02 (dispatch.py
capture) additionally requires the operator per-dispatch approval artifact at dispatch time.
