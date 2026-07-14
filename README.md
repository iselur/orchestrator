# orchestrator — your AI engineering manager

**You bring the idea. One AI manages the work; another builds it.** You write a small spec and
approve it; a worker implements it in an isolated sandbox; deterministic gates check the result;
a reviewer from the *other* vendor judges the exact diff; a pull request lands for you. `main` is
yours alone, permanently.

Today the manager is Claude Code and the worker is Codex. The *rules* are written in roles rather
than model names, so a vendor swap does not rewrite the rulebook — but the scripts still speak each
vendor's command line, so swapping one is a real (small) code change, not a config edit.

## How a task flows

Idea → small spec → your approval (every high-risk dispatch needs it; the manager never writes its
own) → worker builds it in isolation → checks (worktree untouched, changes in scope, tests actually
ran) → cross-vendor review bound to the exact diff → draft PR → you merge.

## Why two vendors

Models from different vendors fail differently, so cross-review is spent where it earns its cost:
grilling ideas, reviewing briefs, judging trust-critical code. Everywhere else, deterministic tests
outrank agreement between models — two models agreeing is not evidence. For worker diffs the
dispatcher structurally enforces the split (the reviewer is a different vendor from the author, with
no tools). Elsewhere it is a rule the orchestrator follows, not a wall the code builds.

## What is checked

- **Spec → approval → worker → checks → review → PR.** Nothing runs without a schema-valid spec and
  an approval file bound to the exact spec digest *and* your instance (a copied approval authorizes
  nothing).
- **Worker isolation, and it fails closed.** The worker *and* the test command (both run
  model-produced code) execute as a dedicated unprivileged `codex-worker` user in hardened `systemd`
  services: your home — and every credential in it — is unreachable, writes are confined to the
  worktree, and the test phase has no network. If that isolation is unavailable, the dispatcher
  refuses to launch (`ORCH_ALLOW_UNISOLATED=1` overrides it; that is full exposure and it is
  recorded). Proven by `tests/worker_isolation.sh` and `tests/worker_userns.sh`.
- **Tests that did not run are not passes.** A skip, a missing result, or an empty required-test set
  fails the gate before the reviewer is invoked. (This repo shipped a false PASS once — a reviewer
  certified three tests that had silently skipped. That is why this gate exists.) It protects
  against accidental skips; the deliberately-malicious-worker case is SECURITY.md gap 3.
- **Review bound to the exact diff and base.** The reviewer has no tools, sees only spec + diff +
  evidence, and its verdict is valid only for the base it was bound to; a stale base is refused.
- **Human-gated merges.** Merges to `main` are human-only — that one is enforced by your GitHub
  ruleset, not by a test in here. Optional autonomy (off by default) lets the orchestrator merge
  gated worker PRs to `integration` only.

## Known limitations — read SECURITY.md

The isolation protects *your* credentials; it is not perfect. Today the worker holds its own Codex
login and has network access during the build phase, approval files record human intent rather than
prove it, the test grade is not yet safe against a deliberately malicious worker, and evidence is an
audit record rather than immutable. `SECURITY.md` states exactly what holds (with the test that
proves it), what is configuration you set up outside this repo (branch protection, the sandbox
profile), and what does not hold yet; the fixes are queued in the backlog. Every claim here is
either backed by a named test or labelled as one of those configured assumptions.

## Quick start (bootstrap it yourself)

You need: an **Ubuntu 24.04** VPS, **Claude Code** installed on it, **Claude** and **Codex**
subscriptions, a **GitHub repo** you own, and (recommended) **Tailscale** for private SSH.

1. Click **"Use this template"** to create your own repo (*default branch only*), clone it onto
   your VPS.
2. In Claude Code on the box, paste:

   ```
   Read BOOTSTRAP.md and set me up gate by gate, pausing at each human step.
   ```

Claude runs the idempotent installers and verification and stops for the steps only you can do
(provisioning, branch protection, and the interactive Claude/Codex logins). Not fully one-click:
those account-bound steps are yours.

## What's in here

| Path | What it is |
|---|---|
| `scripts/dispatch.py` / `scripts/dispatch` | launch, checks, review, merge, health, reconcile |
| `scripts/intake` | task gate: no work without a goal and a checkable definition of done |
| `scripts/review` / `scripts/codex-plan` | bounded cross-vendor review (2 rounds max) / tiered plans and briefs |
| `scripts/setup-worker-user.sh` | one-time privileged host setup for worker isolation |
| `CLAUDE.md` / `AGENTS.md` / `SECURITY.md` | operating rules, role-to-model map and commands, honest security model |
| `specs/`, `.orchestrator/` | specs and the tracked approval/attempt records |
| `tests/` | the repo suite, including isolation drills and the prose/plain-language caps |

## License

MIT — see [LICENSE](LICENSE).
