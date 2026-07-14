# orchestrator

**A safety-first control plane where Claude orchestrates and Codex executes autonomous software work — every change gated, isolated, and human-authorized before it ships.**

You write a small spec, approve it once, and the system: dispatches a Codex worker to implement it in an isolated sandbox, commits and checks the result against integrity/scope/tests, has an independent Claude reviewer pass judgment, and opens a pull request — never touching your credentials and never merging to `main` without a human. It runs unattended on a cheap VPS and you review results after the fact.

> This is the real control plane, built and hardened gate by gate (the full build log, including adversarial design reviews, lives in the repo history and decision records). It's set up so you can stand up your own copy and point it at your own repos.

## What makes it safe

- **Spec → approval → worker → gates → review → PR.** Nothing runs without a schema-valid spec and an approval artifact bound to the exact spec digest *and* your instance (a copied approval can't authorize anything).
- **Worker isolation (the load-bearing part), and it fails closed.** The worker *and* the test command (both run model-produced code) execute as a dedicated unprivileged `codex-worker` user in hardened `systemd` services: your home — and every credential in it — is unreachable, writes are confined to the worktree, and the test phase has no network. Credentials are separated by filesystem permissions, not by trusting a model sandbox. If that isolation is unavailable, the dispatcher **refuses to launch** rather than quietly running model-produced code as you (`ORCH_ALLOW_UNISOLATED=1` overrides it — that is full exposure, not a sandbox, and it is recorded in the evidence).
- **Tests that did not run are not passes.** Required tests must actually execute: a skip, a missing result, or an empty required-test set fails the gate *before* the reviewer is invoked, and the reviewer is handed the orchestrator's per-test attestation rather than an exit code. (This repo shipped a false PASS once — a reviewer certified three tests that had silently skipped. That is why this gate exists; see `.orchestrator/decisions/VERDICT-INTEGRITY/`.)
- **Fail-closed review.** An independent reviewer returns a schema-bound PASS/FAIL bound to the exact diff; the reviewer has no filesystem tools. It is a *second* line of defence, not the first: the deterministic gates above are what actually hold, and the reviewer is not trusted to notice what they miss.
- **Human-gated merges.** Merges to `main` are human-only, permanently. Optional plan-scoped autonomy lets the orchestrator merge to `integration` — off by default, you opt in.
- **Dual-validated planning.** Non-trivial architecture/security/policy decisions are drafted and then adversarially reviewed by a second model before adoption, with the reasoning recorded.
- **Bounded remediation, recovery drills, parallelism with a stale-base guard** — all deterministic and evidence-producing.

## Quick start (bootstrap it yourself)

You need: an **Ubuntu 24.04** VPS, **Claude Code** installed on it, plus **Claude** and **Codex** subscriptions, a **GitHub repo** you own, and (recommended) **Tailscale** for private SSH.

1. Click **“Use this template”** above to create your own repo (choose *default branch only*), then clone it onto your VPS.
2. In Claude Code on the box, paste:

   ```
   Read BOOTSTRAP.md and set me up gate by gate, pausing at each human step.
   ```

Your Claude walks you through it: it runs the idempotent installers and verification, and stops for the steps only you can do (provisioning, your GitHub branch protection, and the interactive Claude/Codex logins).

**Not fully one-click, honestly:** provisioning the VPS, your Tailscale, your GitHub branch protection, and the OAuth/device-auth logins are account-bound and interactive — the bootstrap automates everything else and guides you through those.

## What's in here

| Path | What it is |
|---|---|
| `scripts/dispatch.py` / `scripts/dispatch` | the deterministic control plane (launch, gates, review, merge, integrate, health, reconcile) |
| `scripts/setup-worker-user.sh` | one-time privileged host setup for worker isolation |
| `scripts/init-operator` | reset a fresh copy for a new operator (safe by default) |
| `CLAUDE.md` / `AGENTS.md` | the operating invariants and conventions |
| `specs/`, `.orchestrator/` | example specs and the tracked provenance/approval/attempt model |
| `tests/` | the repo's own suite, including the worker-isolation drills |

## License

MIT — see [LICENSE](LICENSE).
