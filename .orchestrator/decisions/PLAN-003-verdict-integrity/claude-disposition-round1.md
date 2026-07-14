# Claude disposition — SOL critique round 1 of PLAN-003 rev2 (VERDICT: BLOCK)

Tier: Critical (gate/evidence integrity) → iterate on the same revision until Claude + SOL both
report no unresolved blocker. My per-finding disposition below; rev3 must address every SUSTAINED
item. Where I scale an amendment down from SOL's maximal form, the invariant is kept and the
residual is recorded explicitly in the plan — hiding it voids the disposition.

| Finding | Disposition | Notes |
|---|---|---|
| B1 bootstrap self-gating | SUSTAIN, scaled | Add a minimal operator-installed bootstrap verifier BEFORE Dispatch 1: frozen (non-candidate) script + frozen required-test/assertion inventory, run by the operator/Claude on-box against each of Dispatches 1–4; Dispatch 4's activation is validated by this frozen verifier, never by its own tests. A full second gate system is out of scope — record residual. |
| B2 assertion-count vacuity | SUSTAIN | Parent-owned expected-assertion-ID set per required test, exact-set match (no unknown/duplicate/missing). Mutation drill: every substantive assertion in TRUST-class tests, or a per-assertion written justification; representative-per-idiom stays only for non-trust tests. `test_command` output is never test evidence unless attested; `true` never counts as testing. |
| B3 nonce/producer authentication | SUSTAIN | Candidate processes get neither nonce nor event descriptor: helpers scrub attestation env + close FDs before any candidate exec; per-invocation nonces + separate pipes (trusted vs supplemental); trusted controller alone converts outcomes to events. Add the candidate-application-forgery attack tests (env, inherited FD, /proc/ppid). |
| B4 target not frozen | SUSTAIN, scaled | Mandatory tree revalidation: after the test phase and immediately before review AND before PR creation, re-verify worktree == worker_commit (clean status, tree hash match); mismatch = failed_test/failed_review. Read-only bind mount is optional hardening, not required for rev3. |
| B5 race-safe execution + trusted root | SUSTAIN | Concrete mechanism required: root-owned read-only snapshot at /srv/codexwork/installed/<commit> materialized from the exact parent commit with a closure manifest (runner, policy, tests, helpers, fixtures, schema, interpreter identity); no reopen-by-path after verification; add swap/race tests. The operator-home-unreadable point is confirmed correct on this host (D5 DAC boundary). |
| B6 evidence immutability | PARTIAL | Full evidence hashing/sealing is the separate `evidence-hashing` plan (baton action 3) — do NOT duplicate it here. PLAN-003 rev3 adds only: O_EXCL no-replace creation for all NEW attestation/review artifacts + dispatcher-owned (not worker-writable) evidence paths + refusal to reopen a finalized attempt. Cross-reference the evidence-hashing plan for the rest. |
| B7 supplemental namespace isolation | SUSTAIN | Fold into B3 mechanics: separate pipes/nonces, dispatcher-owned aggregation, single-launch proof (side-effect counter). |
| B8 semantic injection claim | SUSTAIN (claim narrowing) | R5.3 claims syntactic prompt integrity ONLY; reviewer stays an untrusted fail-closed oracle layered over deterministic gates; prefer machine-generated attestation summary as primary evidence, log tail secondary. Add raw-log size cap BEFORE hashing (cap enforced at capture). |
| B9 venv identity/shadowing | SUSTAIN, scaled | python -I (isolated), fixed safe cwd, scrubbed PYTHON* env, venv address = hash(requirements + python ABI/platform); verify module origins for yaml/jsonschema resolve under the venv; add candidate shadow-module (yaml.py/sitecustomize.py) tests + fresh-box and python-upgrade tests. Full hash-locked wheelhouse: record as residual/deferred unless requirements.txt already pins hashes. Candidate requirements-change bootstrap: staged (provision from MERGED parent only, never pre-merge). |
| B10 policy coverage | SUSTAIN, scaled | Define the canonical diff model (mode changes, symlinks, submodules, type changes, renames both sides, untracked/dirty = fail closed in control-plane areas); property-test: every changed path yields nonempty required set or policy error. |
| B11 approval-binding contradiction | SUSTAIN (routing) | The approval-schema work is its own plan draft (baton action 4). rev3 must pick: (a) declare dependency on that plan landing first and bind test-blob enumeration through its schema, or (b) drop R7.6's new binding claims to the existing invariant and record the gap explicitly. No silent contradiction. |
| B12 duplicate keys + spec snapshot | SUSTAIN | Reject duplicate JSON keys at parse (object_pairs_hook); persist the digest-approved acceptance-criteria vector in the attempt manifest at launch; validate v4 against that immutable vector; add duplicate-key + spec-swap tests. |
| Operational: activation manifest | SUSTAIN | "Merged and installed" becomes a recorded machine-checked state: an activation manifest (commit, drill results, verifier hash) that the dispatcher requires before dispatching under a new parent; missing manifest = refuse. |
| Operational: Phase 2 gating | SUSTAIN (clarify) | Phase 2 implementation dispatch requires ALL of Phase 1 landed (through Dispatch 5), matching the operator's gate; metrics (Dispatch 2) alone is necessary but not sufficient. |
| Operational: compatibility sequence | SUSTAIN | Specify the full three-state sequence explicitly (transitional test → promote strict test → remove bridge), each stage a normal dispatch. |
| Operational: fresh-box provisioning | SUSTAIN, scaled | One documented + tested provisioning script path (extends setup-worker-user.sh); CI never claims to cover it. |
| Assumption 4 | SUSTAIN | Superseded by B2's per-assertion inventory for trust tests. |
| §8 additions / falsely-green list | SUSTAIN | Fold SOL's 18 missing acceptance tests and the falsely-green mitigations (replay through the REAL gate state machine with reviewer/PR spies; baseline parity hashes captured pre-candidate and approval-bound; metrics window anchoring) into R-numbered acceptance criteria. |

Net effect on decomposition: rev3 should add a **Dispatch 0 (bootstrap verifier + activation
manifest, operator-installed, high-assurance)** and may fold B5's install-snapshot provisioning
into it; Dispatches renumber accordingly. Residual-risk section must list: no full wheelhouse
hash-locking (if deferred), read-only bind mount optional, semantic injection not neutralizable,
full evidence sealing in the separate evidence-hashing plan.
