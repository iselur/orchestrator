# BACKLOG — why we are here, and what is next

New ideas land here, never into flight; work starts only via `scripts/intake` with a definition of
done. A real product outside this repo must always be on this list (CI checks it is never without one).

## Why (the operator's own description of what this system is for)

A combination of an **AI engineering manager and AI engineers**: the orchestrator manages, judges,
reviews, and holds the trust boundary; the workers plan, research, implement, and test. The
capability the operator wants is end to end — drop an idea on it and it grills the idea, reconciles
a recommendation, breaks it into tickets, logs them, improves the plan, executes, reviews the
result, tests it, deploys it, and maintains what it ships. Every holistic review measures the setup
against this description: what matches, what doesn't, what is missing.

## Next up (operator-ordered 2026-07-16)

1. **Codex priority tier fast → standard** (cost lever from the 2026-07-15 token findings; owner
   2026-07-16): flip worker/reviewer/spec-author Codex calls to standard processing; watch dispatch ceilings.
2. **Program C (rev 4)** — thin orchestrator, specialists, authoring flip, unpin `CLAUDE_CODE_SUBAGENT_MODEL`.
   Reshape in flight as R83–R86; C2 (review round binding) shipped, C1bc and C3 remain.
3. **Ship a real product, end to end** — top idea from `~/orchestrator-private/IDEAS-shortlist/`,
   its own repo, one small feature through idea → brief → tickets → build → test → review → merge → running.
   product: new repo from the private shortlist (name it at intake)
4. **Restrict worker build-phase egress before the first product-repo dispatch** (SECURITY.md gap 1,
   LOW-MEDIUM 2026-07-16): worker uid reaches only the model API; the credential-broker fix stays parked.

## Parked (owner 2026-07-16: keep for the future)

- In-flight session-to-session handoff (deferred from the R77 descope, owner 2026-07-16): atomic
  handoff commit/consumption, duplicate suppression, mid-handoff crash recovery. If revived, take
  the Python falsifier route; scenario matrix preserved on branch orch/r77-lifecycle-falsifier.
- Approvals rework (SECURITY.md gap 2): the autonomy grant covers low risk, owner confirms `main` only.
- Move the test grade out of the worker's reach (SECURITY.md gap 3).
- Measure whether review catches bugs: plant three known defects, count catches, size review scope from the result.
- 2026-07-15 audit remainder: re-verified 2026-07-16 — seven of eight highs already fixed on main,
  the last a low-risk merge-window race (owner enables GitHub's up-to-date-branch rule); four
  state-machine mediums confirmed but low risk. Report: claude-out/audit-reverify-2026-07-16.md.
- Fable retirement follow-through: after the owner's manual flip, point the bound reviewer in
  `scripts/models.json` at its successor via a reviewed PR.
- External benchmark score and cost reporting — after a real product exists.
