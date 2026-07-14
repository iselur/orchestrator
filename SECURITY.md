# SECURITY — what actually holds, and what does not yet

This file is the source of truth for the security model. A claim may appear in README or CLAUDE.md
only if a test listed here proves it. Known gaps stay listed until a shipped fix closes them.

## Guarantees, each with its proof

| Guarantee | Proof |
|---|---|
| Worker commands cannot read the operator's home or any credential in it | `tests/worker_isolation.sh` (box-only) |
| No isolation → no launch; the override requires the operator to type it | `tests/isolation_fail_closed.sh` |
| A test that did not run did not pass; empty required set fails; worker-edited required tests are restored from the orchestrator's checkout before grading | `tests/test_attestation.sh` |
| Worker changes outside the spec's declared scope are rejected | `tests/dispatch_gate4.sh`, `tests/scope_glob.sh` |
| A verdict is bound to the exact diff and base; a stale base is refused | `tests/dispatch_gate4.sh` |
| Direct pushes to `main` are rejected; `integration` requires a PR with `ci` green | GitHub ruleset (verified during bootstrap) |
| The rulebook and repo prose cannot silently grow back | `tests/rulebook_cap.sh`, `tests/prose_cap.sh`, `tests/plain_language.sh` |
| Review rounds are capped at two per topic, in code | `tests/review_cap.sh` |

## Known gaps (fixes queued in `.orchestrator/BACKLOG.md`)

1. **The worker holds its own Codex login and has network in the build phase.** Setup copies Codex
   auth into the worker's home so the worker can run Codex at all, and the build-phase service is
   not network-blocked (the test phase is). Model-produced commands therefore share an environment
   with readable Codex login files and a network path out. The operator's own credentials remain
   unreachable — but "workers get no network / no credentials" is not yet true and is not claimed.
2. **Approvals record intent; they do not prove a human.** An approval is a JSON file; the
   isolation override is an environment variable. Software running as the operator could create
   either. They are an audit trail, not an authorization boundary. A mechanism Claude cannot
   fabricate (e.g. GitHub environment approval or a separate human-held account) is the planned
   replacement.
3. **The test grade is produced inside worker-writable territory.** The per-test result file lives
   in the worktree, and `scripts/test` itself is not part of the restored required set — a worker
   that edits the runner could in principle influence its own grade. The grader must move fully
   outside the worker's reach.
4. **Evidence is an audit record, not immutable.** Attempt files and their hashes are ordinary
   files owned by the account that writes them. Treat them as good-faith provenance.
5. **The dispatcher currently targets this repository.** Pointing workers at an arbitrary product
   repo is planned but not yet a tested interface.

## Scope

Single-operator system on a private VPS. No external vulnerability reports are expected; if you
run a copy and find a hole, open an issue on the template repo.
