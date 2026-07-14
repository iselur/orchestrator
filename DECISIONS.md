# DECISIONS — one line per decision that still binds

Full arguments live in git history and PR descriptions; a decision earns a line here only while it
still constrains future work.

- 2026-07-13 — Two branches: `main` is human-only forever; `integration` changes only via PR with
  `ci` green.
- 2026-07-13 — Worker isolation: model-produced code runs as the dedicated `codex-worker` user in
  hardened systemd services, operator home unreachable; launch refuses if isolation is missing.
- 2026-07-13 — Approval gate: high-risk specs need a per-dispatch operator approval file bound to
  the spec digest and this instance; Claude never creates one.
- 2026-07-13 — Tests must run to pass: a skip is never a pass; required tests are restored from
  the orchestrator's own checkout before grading (a reviewer once certified three silently-skipped
  tests as passing — that failure funds this rule).
- 2026-07-13 — Cross-model review on the exact diff; never self-review; verdicts bind and are
  valid only for the base they were bound to.
- 2026-07-13 — Codex does most execution and research; Claude orchestrates, reviews, reports.
- 2026-07-13 — Business ideas and the request ledger are private, never in the public repo.
- 2026-07-13 — Plan-scoped autonomy (gated merges to `integration` via `dispatch merge` only)
  ratified for this practice repo; ships disabled in the template.
- 2026-07-14 — Runaway plan-review loops halted (one reached ten rounds and was replaced by a
  ~50-line hand fix); review rounds capped at two, now enforced in code by `scripts/review`.
- 2026-07-14 — Lean rules adopted: intake gate, one workstream, review cap, plain 5-bullet
  reports, one brief per program; CI caps the rulebook's size.
- 2026-07-14 — Lean reset: ~35,000 lines of process prose deleted (archived in the private repo);
  prose total, file allowlist, and plain language now CI-enforced; docs claim only what tests
  prove; the backlog's top item must be a real product outside this repo.
