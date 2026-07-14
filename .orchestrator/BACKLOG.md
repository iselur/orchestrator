# BACKLOG — ideas and deferred work (R29 rule 2: one workstream at a time)

New ideas land here, not into flight. Pulling an item into work requires intake
(`scripts/intake`) with a definition of done.

## Next up (operator-ordered)
1. **External benchmark as the factory's score** (R28) — run the factory against a public coding
   benchmark it did not author (SWE-bench Verified class); preregister the baseline BEFORE any
   capability claim. This is the finish line every later change is measured against.
2. **Reflect + remember** (R28) — cross-vendor reflection on failed attempts; durable lesson
   ledger where a lesson stays a hypothesis until the benchmark validates it; prune what never
   pays off.
3. **Telemetry** (R28) — every run emits cost, wall-clock, gate outcomes as read-only evidence.
4. **Budget model** (R28) — what to build next is chosen under an explicit token/$ budget.
5. **Capability-delta gate** (R28) — a change ships only if it holds-or-improves the benchmark
   score and regresses no safety counter.

## Parked
- Continuation/timer replacement (R23) — the outer loop that survives box limits; redesign after
  the benchmark exists so the loop has something real to drive.
