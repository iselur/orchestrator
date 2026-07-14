The amended design still leaves worker-authored TEST code able to read operator credentials from disk and communicate through host-local channels. A network namespace plus environment scrub is not a credential boundary for code retaining the operator’s host identity. That is design-blocking.

I could not independently re-read the repository because the read-only command sandbox failed before execution with `bwrap: loopback: Failed RTM_NEWADDR`. Code-path references below therefore rely on the challenge’s quoted HEAD audit rather than claiming fresh verification.

1. **BLOCKING — Same-user TEST retains filesystem access to operator credentials.**  
   Unmapped `unshare --user` makes the child *display* UID 65534, but it does not turn it into an unrelated host user. The challenge’s successful write demonstrates the important property: host VFS checks still permit operator-owned worktree access. The same mechanism permits reads of operator-readable paths such as `.codex/auth.json`, `.ssh/*`, cloud configuration, browser stores, and arbitrary credential locations. Environment scrubbing does nothing to those files.

   Worse, network isolation does not prevent eventual exfiltration. TEST can print a secret into captured output, write it into the worktree/evidence, alter files consumed by remediation or review, or plant data for a later network-enabled worker. The canary acceptance test only checks that an environment token is absent; it must also plant a disk canary and require that TEST cannot read it. Under the proposed launcher, that test will fail.

   This requires a filesystem boundary: a separate host UID, VM, or a mount-root sandbox exposing only the worktree and deliberately selected runtime files while hiding the operator home, `/run/user/$UID`, host `/proc`, and other writable shared state. If that cannot be provided, TEST must refuse.

2. **BLOCKING — Credential assessment cannot safely authorize same-user execution.**  
   The registry misses many common or generic forms:

   - Environment names containing `AUTH`, `BEARER`, `SESSION`, `COOKIE`, `JWT`, `LOGIN`, or merely `KEY`; secrets in generic variables; command-line arguments; and systemd credential variables.
   - `KRB5CCNAME`, `KRB5_KTNAME`, `GNUPGHOME`, `AWS_CONFIG_FILE`, `AZURE_CONFIG_DIR`, `npm_config_userconfig`, `PIP_CONFIG_FILE`, custom Git credential helpers, credential-cache sockets, PKCS#11 stores, browser profiles, kernel keyrings, Secret Service, and files outside registered roots.
   - SSH keys with arbitrary names or outside `.ssh`. “Non-public-key material” cannot be determined reliably using metadata alone without either treating almost every `.ssh` entry as credential-bearing or inspecting contents.
   - Credentials reachable through hard links, parent-directory symlinks, bind mounts, configured relative paths, or sockets under `/run/user/$UID` and `/tmp`.

   Resolving passwd-home plus `$HOME` is directionally correct, but neither is authoritative for all applications. Every configured path needs application-correct relative-path semantics; final-component `lstat` is insufficient when an ancestor is a symlink.

   There is also unavoidable TOCTOU: credentials can appear after selection, after the immediate worker recheck, or before either TEST/regression execution. Symlinks and credential pointers can change during the attempt. Rechecking before every untrusted launch reduces the window but does not close it. Therefore “no registered credential found” cannot be treated as proof that same-user execution is safe; it is only an operational warning signal.

3. **BLOCKING — The execution-mode state machine must cover more than the named TEST call.**  
   The supplied HEAD audit identifies independent decisions in [`worktree_root()`](/home/val/orchestrator/scripts/dispatch.py:540) and launch selection near [`dispatch.py:717`](/home/val/orchestrator/scripts/dispatch.py:717), the current fallback worker near [`dispatch.py:860`](/home/val/orchestrator/scripts/dispatch.py:860), fallback TEST near [`dispatch.py:946`](/home/val/orchestrator/scripts/dispatch.py:946), and the unprotected regression branch in [`run_regression_gate()`](/home/val/orchestrator/scripts/dispatch.py:623). These must all consume one immutable decision.

   The inventory must explicitly include:

   - Initial worker launch and every retry.
   - Remediation Codex launches and any commands they execute.
   - Primary TEST.
   - Both base-overlay and candidate regression runs.
   - Review Codex processes if they can invoke tools or repository commands.
   - Any post-test validation or Git hook-capable command operating on worker-controlled state.

   A same-user Codex worker is itself dangerous: it can execute model-directed shell commands with the operator’s filesystem identity and network. `ORCH_ALLOW_UNISOLATED=1` therefore authorizes full worker exposure, not merely a less-isolated launcher followed by a safe TEST.

   Preflight must occur before attempt-directory creation and before `claim_slot`. `worktree_root` must take the selected decision rather than calling `isolation_available()` again. An isolated launch failure, timeout, cleanup failure, retry, or remediation transition must never recalculate and downgrade the mode.

4. **BLOCKING — The network proof is valid only for direct IP networking, not exfiltration.**  
   A fresh network namespace with no interfaces or routes prevents direct access to parent loopback and external IPv4/IPv6. It also isolates Linux abstract Unix sockets. It does **not** isolate pathname Unix sockets, which are governed by filesystem visibility. [Linux’s namespace documentation confirms that distinction](https://www.man7.org/linux/man-pages/man7/network_namespaces.7.html).

   Consequently, TEST may still reach predictable pathname sockets for D-Bus, SSH/GPG agents, Docker/Podman, systemd user services, credential caches, Secret Service, resolver proxies, or custom operator daemons. Those services can expose credentials or act as host-network relays. A network namespace also leaves SysV/POSIX IPC and shared memory visible unless IPC and mount namespaces are added. [IPC namespaces isolate only their specific IPC resources](https://man7.org/linux/man-pages/man7/ipc_namespaces.7.html).

   `close_fds=True` handles accidental inherited descriptors, but stdout/stderr are deliberate cross-boundary descriptors and can carry stolen data into evidence. The shared host `/proc` remains another attack surface; access to other processes’ environment, descriptors, and state depends on ptrace checks and host LSM policy, which is not a portable security guarantee. [Linux documents `/proc` access as using ptrace-style credential checks](https://man7.org/linux/man-pages/man2/ptrace.2.html).

5. **CONDITION — The mapped/unmapped probe ladder is not itself a direct-IP downgrade, but it must select an exact immutable submode.**  
   Trying mapped mode and then an unmapped probe is acceptable only during preflight. Once one succeeds, record `SAME_USER_MAPPED` or `SAME_USER_UNMAPPED` and use that exact argv for every real TEST/regression invocation. The real payload must never be tried once under one mode and retried under another or without `unshare`.

   The challenge is internally imprecise in calling unmapped mode “primary” while specifying mapped-first probing. Choose and document one ordering. Given the host evidence, unmapped-first is simpler unless mapped identity is required for compatibility.

   The `git status` plus write probe establishes workload compatibility, not security. It should use the same environment, shell, `--fork` behavior, cwd class, executable paths, and namespace flags as the real launcher. A later failure remains terminal. Validate the resolved `unshare` binary and its parent directories; avoid PATH lookup. Root ownership alone does not address a replaceable symlink or writable ancestor.

6. **BLOCKING — Process lifecycle containment is absent.**  
   Worker TEST can daemonize or double-fork. Killing or waiting for the shell does not prove all descendants terminated. Such descendants can continue reading or modifying shared filesystem state after the gate, including while a later network-enabled review or remediation runs.

   The launcher needs a new PID namespace plus a reliable whole-tree kill mechanism, preferably a cgroup or equivalent. Util-linux documents that `--kill-child` combined with a PID namespace supports killing the tree, while ordinary `--fork` has non-obvious signal behavior. [See `unshare(1)`](https://man7.org/linux/man-pages/man1/unshare.1.html). Validation must include a double-fork escape attempt and prove no descendant survives timeout, interrupt, ordinary completion, or infrastructure failure.

7. **BLOCKING — All 15 proposed cases can pass vacuously without stronger positive controls.**

   - Cases 1–8 can succeed because an earlier parse error, ambient credential, or failed namespace probe prevented any relevant launch. Each must assert the exact decision reason and positive launch markers in its opposite branch.
   - Cases 2–4 need a scrubbed fixture plus removal controls proving that removing the targeted indicator changes the outcome.
   - Case 5 must prove literal `1` actually launches the expected same-user path; a later namespace refusal is not success.
   - Case 6 must reach a real fake worker, not merely return an enum.
   - Case 8 must prove the isolated launcher was invoked and failed before asserting no fallback.
   - Cases 9–10 need hostile parent variables, startup hooks, global Git configuration, and real disk canaries. Merely observing a temporary HOME does not prove the old home is inaccessible.
   - Case 11 proves only namespace identity, not isolation properties.
   - Case 12 needs listener-readiness synchronization, a successful parent-namespace positive connection, proof the child attempted the connection, and zero sandbox accepts.
   - Case 13 needs a payload marker and a failure injected after the real launcher is selected; otherwise “payload did not run” proves little.
   - Case 14 needs proof the payload executed and that its exit was classified as an ordinary gate failure rather than infrastructure refusal.
   - Case 15 cannot be satisfied by searching for `SKIP`; tests can return success early without using that word.

   The falsifiable acceptance test likewise needs a valid-spec positive control, exact preflight status assertions, before/after durable-state snapshots, scans of stdout/stderr and all created evidence, and disk/proc/pathname-socket canaries. Its current environment-token check is insufficient.

8. **BLOCKING — “Assert refusal where userns is unavailable” does not validate the launcher.**  
   Refusal is the correct result on a restricted host and should be tested instead of skipped. But it proves only fail-closed selection. It does not exercise environment scrubbing, namespace entry, regression routing, loopback denial, process cleanup, or actual payload execution.

   A misconfigured host can therefore produce a green suite while never testing the hardened path. Validation needs two mandatory environments:

   - One where user namespaces are deliberately unavailable and refusal is proven.
   - One where the selected unmapped mode works and every launcher/security test actually executes.

   A local refusal-only result should be reported explicitly as incomplete security validation, not as the full suite passing.

9. **CONDITION — Folding the non-vacuous `worker_isolation.sh` drills into this work is appropriate.**  
   This is not material scope bloat: it touches an already relevant test, exercises the same boundary, and prevents the change from being declared safe using hard-coded or absent credential targets. Splitting it creates a greater risk that the implementation merges with theater coverage.

   Keep it reviewable as a distinct commit or clearly separated test section. Resolve operator home dynamically; create a harmless positive canary; prove the operator can read it; prove the isolated worker cannot; fail if the canary was never created or the probe never ran; and clean it reliably without touching real credential files.

10. **BLOCKING — Strongest counterargument: do not build a “safe” same-user fallback at all.**  
    The strongest objection is that credential discovery is inherently incomplete and same-user code cannot be denied same-user files by ordinary DAC. Adding only environment and network isolation risks converting an obvious fail-open into a boundary that looks credible but is not.

    That objection is correct. The urgent, defensible shipment is the minimal fail-closed rule: when D5 is unavailable, refuse before durable state or code execution. If a break-glass override must remain, it must be described as explicit acceptance of full operator-credential and host-state exposure—not as a protected fallback—and should require separate human authorization. A genuinely protected fallback can follow only after it has filesystem, pathname-IPC, `/proc`, descendant-lifecycle, and network containment, with mandatory non-vacuous validation.

VERDICT: BLOCK
