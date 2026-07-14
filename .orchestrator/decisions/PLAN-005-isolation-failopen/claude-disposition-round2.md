# Claude disposition — SOL round 2 of PLAN-005 rev2 (BLOCK, 2 findings)

The frozen-mode selector, the six execution sites, no-downgrade tests, exposure-mode naming, and the
two mandatory environments are explicitly ACCEPTED. Two findings remain; both SUSTAINED — finding 1
is security-material, finding 2 is a vacuous-test hole. (Both clear my stop-rule's blocking bar.)

## Finding 1 — authorization collapses after one authorized exposure. SUSTAIN.

The critique is exactly right and I missed it: exposure mode grants the payload the OPERATOR EUID by
definition, so ANY authorization artifact or consumption record stored under operator ownership is
forgeable/erasable by the very payload it authorized. One authorized exposure ⇒ unlimited silent
future exposures. The "requires human authorization" claim is unvalidatable.

**Chosen mechanism (minimal, reuses infrastructure we are already building):**
- Break-glass tokens are **single-use, derived from a root-held secret**, and are **not storable by
  the operator UID as a reusable credential**: the operator obtains one out-of-band (a root-owned
  helper prints it on an explicit interactive sudo invocation; the operator pastes it into the
  dispatch invocation).
- Redemption is **atomic, root-owned, append-only**: a tiny scoped-sudoers helper (the same scoped
  sudoers wrapper already queued as baton action 5) validates the token against the root-held
  secret, records redemption in a **root-owned append-only ledger the operator UID cannot modify or
  delete**, and refuses replay. Every binding field (spec_digest, attempt id, base_sha, expiry) is
  covered by the token derivation.
- Consequence stated plainly in the plan: with no root helper installed, break-glass is
  **unavailable** (dispatch simply refuses) — fail-closed, not fail-open-with-a-file.
- Regression: an authorized exposure payload attempts to forge an artifact, erase its consumption
  record, and replay; every subsequent dispatch must still refuse without a fresh human token.

## Finding 2 — canary drill has no positive control for the WORKER-side read primitive. SUSTAIN.

Add a second, deliberately worker-READABLE control token. The SAME service, probe implementation,
and path-passing mechanism must read and compare it successfully BEFORE the protected-home canary is
attempted. Separate markers required for: control-read-succeeded, protected-path-attempted,
denial-observed. Probe/tool failure is a DRILL FAILURE, never "isolation confirmed". Sabotage cases:
skip the read, break the probe command, pass a wrong path — each must make the drill fail red.
