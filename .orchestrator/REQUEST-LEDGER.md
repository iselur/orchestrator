# REQUEST-LEDGER — every operator request, tracked to completion (no slippage)

Appended at INTAKE, before work (CLAUDE.md "NO SLIPPAGE"). Reconciled at the end of every turn. A row
must reach `done` or an explicit operator deferral — a stalled row is a surfaced process failure.

| id | date | request (intent) | lane | plan-ref | status | completion-evidence |
|----|------|------------------|------|----------|--------|---------------------|
| R01 | 07-13 | Finish #1 regression-proof gate | high-assurance | — (pre-ledger) | done | PR #34; run_regression_gate |
| R02 | 07-13 | Rebalance to Codex / execution split | control-plane | REBALANCE-codex | done | PR #35; CLAUDE.md |
| R03 | 07-13 | Ratify delegate-first + MAX delegation | control-plane | REBALANCE-codex | done | CLAUDE.md |
| R04 | 07-13 | Codex full toolkit / web search | control-plane | REBALANCE-codex | done | CLAUDE.md |
| R05 | 07-13 | Diff-blindness explain + first delegated spec | ordinary | SPEC-014 | done | PR #36/#37 |
| R06 | 07-13 | Reviewer quality params (v3) | high-assurance | SPEC-015-quality-rubric | done | PR #38 |
| R07 | 07-13 | Spec-drafting delegation + plan-first | control-plane | PLAN-001 | done | PR #39 |
| R08 | 07-13 | Strict planning + Codex drafts plans | control-plane | PLAN-001 | done | codex-plan (SPEC-016); PR #39 |
| R09 | 07-13 | Rules in GitHub? + IDEAS-* untracked | — | — | **OPEN** | operator decision pending: commit/move IDEAS-* on public repo? |
| R10 | 07-13 | Holistic self-reflection, plan first | control-plane | PLAN-002 | done | SELF-REFLECT-2026-07/ |
| R11 | 07-13 | Harness best-on-data: telemetry+dashboard+golden dataset | high-assurance | MEASUREMENT-layer | **IN-PROGRESS** | plan drafted; Phase 2 in baton; NOT built |
| R12 | 07-13 | Keep capacity, re-audit 2wk, don't pause, 5h routines | control-plane | 06-reconciled | done | trig 2026-07-27; timer; PENDING |
| R13 | 07-13 | On-box (Hetzner) tracker | control-plane | — | done | orchestrator-continue.timer |
| R14 | 07-13 | 5h trigger only if unfinished work | control-plane | — | done | continue-session.sh gate |
| R15 | 07-13 | Verify verdict job broken; delegate to Codex | high-assurance | VERDICT-INTEGRITY | done (investigation); fix IN-PROGRESS | response.md: BROKEN 1/14; fix queued in baton |
| R16 | 07-13 | Delegate all remaining tasks to Codex | high-assurance | 7 drafts | **IN-PROGRESS** | .orchestrator/plans/drafts/* |
| R17 | 07-13 | Share work plan (BLUF) | — | — | done | conversational |
| R18 | 07-13 | Audit requests for slippage + reinforce planning | control-plane | REQUEST-AUDIT | **IN-PROGRESS** | Codex audit running; this ledger + CLAUDE.md NO-SLIPPAGE |

## Open / in-progress (the anti-slippage watchlist)
- **R09** OPEN — needs an operator decision (public-repo IDEAS-* handling).
- **R11** IN-PROGRESS — measurement layer: Phase 2, gated behind verdict-integrity + metrics fix.
- **R15/R16/R18** IN-PROGRESS — verdict-integrity fix, 7 action-item plan-drafts, this audit.
