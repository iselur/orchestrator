# BACKLOG — ideas and deferred work, one workstream at a time

New ideas land here, never into flight. Pulling an item into work requires `scripts/intake` with a
definition of done. Item #1 must be a real product outside this repo (CI checks this).

## Next up (operator-ordered)

1. **Ship a real product, end to end** — pick the top idea from the private shortlist
   (`~/orchestrator-private/IDEAS-shortlist/`), give it its own repo, and push one deliberately
   small feature through idea → brief → tickets → build → test → review → merge → running.
   This is the finish line every process change is judged against.
2. **Close the worker credential/network gap** (SECURITY.md gap 1): remove or broker the Codex
   login exposure and block build-phase network, or state per-spec why it must stay.
3. **Make approvals human-provable** (SECURITY.md gap 2): replace file/env-var approvals with a
   mechanism software on this box cannot fabricate.
4. **Move the test grade out of the worker's reach** (SECURITY.md gap 3): result file outside the
   worktree; protect `scripts/test` like the tests it runs.
5. **Measure whether review catches bugs**: plant three known defects, run the normal pipeline,
   count catches; set review scope based on the result, not on faith.

## Parked

- Unattended continuation (an outer loop that survives session limits) — redesign only after a
  real product exists, and only with an alert that fires when it silently does nothing.
- External benchmark score and cost/telemetry reporting — same condition.
