You are an adversarial design reviewer for a trust-critical change to a dispatch orchestrator. You have
NOT seen any prior conversation about this work — judge only what is in front of you. The repository is
readable at your working directory (read-only sandbox); verify claims against the actual code in
scripts/dispatch.py and tests/ where you can.

DECISION UNDER REVIEW (Critical tier — trust/security boundary): close the "isolation fail-open" in
scripts/dispatch.py. Today, when D5 isolation (codex-worker UID + systemd hardening) is unavailable,
the dispatcher silently falls back to running the untrusted worker AND the test/regression phases as
the operator, with inherited environment and network. The attached draft plan (drafted by a separate
Codex session) proposes a fail-closed preflight + hardened same-user TEST launcher. The attached
challenge (written by the orchestrating Claude, with live host evidence) proposes amendments, notably:
use `unshare --user --net` WITHOUT --map-current-user (Ubuntu 24.04 AppArmor denies unprivileged
uid_map writes; verified on this host), route run_regression_gate's same-user branch through the same
hardened launcher, and fold the "non-vacuous isolation drills" audit action (dynamic operator home,
positive canary secrets in tests/worker_isolation.sh) into this plan's scope.

YOUR TASK — adversarial review of the AMENDED design (draft + challenge amendments together):
1. Attack the credential-assessment design: enumerate bypasses (credential forms it misses, TOCTOU,
   $HOME vs passwd-home games, symlink/permission tricks) and say which matter given the stated threat
   model (worker-authored code running in the TEST phase; operator credentials on disk).
2. Attack the execution-mode state machine: any path where a launch, retry, remediation, regression, or
   review step can still execute worker code outside the selected mode? Any downgrade-after-selection
   hole the amended plan leaves open?
3. Attack the network proof: is an UNMAPPED user+net namespace (uid 65534, only a DOWN loopback)
   sufficient to prevent exfiltration by the test phase? What still crosses it (abstract vs pathname
   unix sockets, already-open fds, /proc, dbus)? Is the capability-probe design (mapped-first,
   unmapped-fallback, representative git+write probe, refuse when userns unavailable) sound, or does
   the fallback ladder itself create a weaker-mode hole?
4. Attack the validation: which of the plan's 15 automated cases + canary acceptance test could pass
   VACUOUSLY (test theater)? Does asserting the refusal branch on userns-restricted hosts (instead of
   SKIP) actually keep the suite honest, or does it let a misconfigured box masquerade as tested?
5. The scope amendment (folding the worker_isolation.sh non-vacuous-drills work in): does it bloat a
   trust-critical change past reviewability, or is splitting it the greater risk?
6. State the strongest counterargument to shipping the amended plan at all, and address it.

VERDICT CONTRACT (mandatory): end with a line `VERDICT: PASS` or `VERDICT: BLOCK`, preceded by a
numbered list of findings, each labeled BLOCKING / CONDITION / ADVISORY. PASS may carry CONDITIONs
(must-fix-before-merge items that do not invalidate the design). BLOCK means the design must change
before implementation. Address the strongest counterargument explicitly, questionable assumptions,
failure modes, and validation gaps. Do not soften: a wrong PASS here exposes operator credentials to
worker-authored code.
