One executability-blocking inconsistency remains:

- R1.3 and §4.4 require the installed repository dispatcher to measure itself and verify the installation record before attempt creation or candidate launch. However, Dispatch 0 does not authorize changes to `scripts/dispatch.py`, and Dispatch 2 authorizes that file only for enumerated gate/review functions that exclude installed-parent verification. The current parent cannot reasonably already implement verification of the newly introduced installation-record format. A launcher-side check would preserve much of the security outcome, but it would not satisfy the plan’s explicit dispatcher-self-check claim.

Resolve this by either:

- authorizing the required `scripts/dispatch.py` changes in Dispatch 0; or
- changing R1.3/§4.4 to make the root-owned launcher perform the check, removing the dispatcher-self-check claim.

The remaining kernel is internally coherent: exact parent-owned assertion sets reject vacuity; controller-only events and UID/namespace separation address forgery; direct-run artifacts lack authoritative adoption paths; verdict v4 binds the complete persisted criteria vector and fails closed on blockers; and the three-dispatch bootstrap otherwise truthfully relies on operator installation and human review. The explicitly deferred race, activation, sealing, and bootstrap-verifier risks are not blockers under R24.

VERDICT: BLOCK
