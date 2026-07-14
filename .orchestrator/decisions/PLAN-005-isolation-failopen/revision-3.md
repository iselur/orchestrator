---
id: PLAN-005
revision: 3
created: 2026-07-14
author: gpt-5.6-sol
status: challenged
ledger_ref: R16
lane: high-assurance
supersedes: PLAN-005 revision 2
---

# PLAN-005 — Refuse dispatch when D5 isolation is unavailable

> **Brief-caliber standard (operator, 2026-07-13):** every plan artifact must reach the depth of the
> original SETUP-BRIEF — a standalone document detailed enough that an agent can execute it
> autonomously with NO further clarification. Not a bullet sketch. If a section is genuinely N/A, write
> "N/A because …". Codex drafts to this template; Claude challenges + authorizes; both then follow it.

## 1. Decision & non-goals

Dispatch will make one immutable execution-mode decision after validating the requested spec and before `claim_slot`, attempt-directory creation, branch/worktree creation, or execution of worker-authored code. If D5 isolation is available, every worker, TEST, regression, retry, remediation, and related execution path must use it. If D5 isolation is unavailable, dispatch must refuse without creating durable attempt state or launching code, unless the operator supplies both the exact invocation-scoped value `ORCH_ALLOW_UNISOLATED=1` and a valid, unused, invocation-bound single-use token derived from a root-held secret. The token must be obtained out-of-band through an explicit interactive `sudo` invocation of a root-owned issuance helper and atomically redeemed through a scoped-sudoers helper into a root-owned append-only ledger that the operator UID cannot modify or delete. If the root helpers or required scoped-sudoers policy are unavailable, break-glass is unavailable and dispatch refuses. That exception is named and documented as `UNISOLATED_EXPOSURE`: it accepts full exposure of operator credentials and host state and provides no security boundary.

Non-goals:

- Building, describing, or testing a “hardened” same-user fallback.
- Detecting whether operator credentials happen to exist. Credential discovery is not a safe authorization predicate.
- Adding environment scrubbing, user/network/mount/PID namespaces, filesystem filtering, IPC filtering, descendant containment, or an `unshare` capability ladder.
- Claiming that break-glass execution protects secrets, files, sockets, processes, or the host network.
- Redesigning the established `codex-worker` UID, hardened systemd services, ACL layout, `/srv/codexwork/worktrees`, or `scripts/setup-worker-user.sh`.
- Changing spec semantics, gate order, branch targets, merge authority, or review policy.
- Solving unrelated audit findings.
- Making break-glass persistent, automatic, reusable, or suitable for normal operation.
- Auto-merging this trust-critical change.

The deleted hardened-fallback requirements are preserved in this plan only as an entry bar for any future proposal.

## 2. Current-state evidence (facts, with citations)

### Repository facts reported and re-verified by the challenge

Claude’s 2026-07-14 challenge re-verified the following at commit `995cc13`. These are quoted audit facts, not a claim that this revision independently re-read the repository:

- [`scripts/dispatch.py:527`](/home/val/orchestrator/scripts/dispatch.py:527) contains the isolation availability decision whose false result currently permits silent fallback instead of refusal.
- [`scripts/dispatch.py:540`](/home/val/orchestrator/scripts/dispatch.py:540) calls `isolation_available()` independently while selecting the worktree root.
- [`scripts/dispatch.py:623`](/home/val/orchestrator/scripts/dispatch.py:623) begins `run_regression_gate`; its same-user branch near line 649 executes both worker-authored regression runs as the operator with an inherited environment and host networking.
- Durable attempt setup currently begins around [`scripts/dispatch.py:701`](/home/val/orchestrator/scripts/dispatch.py:701), with `claim_slot` recording `launching` state around line 707.
- [`scripts/dispatch.py:717`](/home/val/orchestrator/scripts/dispatch.py:717) performs another independent isolation decision for launch behavior.
- [`scripts/dispatch.py:860`](/home/val/orchestrator/scripts/dispatch.py:860) begins the fallback worker launch, which runs Codex as the operator with host access.
- [`scripts/dispatch.py:946`](/home/val/orchestrator/scripts/dispatch.py:946) begins the fallback TEST launch; the quoted implementation near lines 946–949 is equivalent to `run(["bash", "-c", test_command])`, inheriting the operator environment, UID, filesystem access, and network.
- `AGENTS.md` defines the intended D5 boundary: worker and gate TEST run as `codex-worker` in hardened systemd services, their worktrees live below `/srv/codexwork/worktrees`, and the operator’s home and credentials are inaccessible.
- `./scripts/test` is the repository test entry point and discovers `tests/*.sh`.

Before implementation, the executor must re-inventory these locations at the implementation HEAD. The inventory must include initial worker launch, retries, remediation launches, primary TEST, both regression runs, review processes that can execute tools, and post-test commands capable of running worker-controlled hooks or configuration. If the control flow has materially changed, implementation must stop and PLAN-005 must be re-challenged rather than partially applied by stale line number.

### Host facts retained as background

The challenge also verified on Ubuntu 24.04.4, kernel 6.8.0-111:

```text
unshare --user --map-current-user --net /bin/true
# fails while writing /proc/self/uid_map: Operation not permitted

unshare --user --net /bin/true
# succeeds
```

The reported cause is the host’s AppArmor restriction on unprivileged user-namespace UID mapping. These facts explain why revision 1’s mapped-user probe was invalid on the primary host. They do not select or validate any mechanism in revision 2: the entire probe ladder and namespace fallback have been deleted.

### Security fact governing the redesign

Same-user code retains the operator’s host filesystem identity for ordinary VFS access even when it displays an overflow UID inside an unmapped user namespace. It can therefore read operator-readable credential files, interact through visible pathname sockets and shared host facilities, write secrets into output or the worktree, and leave descendants or state for later processes. Environment and IP-network isolation alone cannot establish the required credential boundary.

The same fact means an exposure-mode payload can forge or erase any authorization material controlled by the operator UID. Break-glass issuance and redemption must therefore cross a root-owned trust boundary that exposure-mode payloads cannot forge, modify, or delete.

## 3. Requirements & acceptance criteria (numbered, testable)

1. **Single preflight decision.** For each dispatch invocation, `isolation_available()` shall be evaluated exactly once for execution-mode selection, after spec parsing and schema validation but before `claim_slot`, attempt-directory creation, branch/worktree creation, or any worker, TEST, regression, review, retry, or remediation execution.

2. **Default refusal.** If that evaluation returns false and `ORCH_ALLOW_UNISOLATED` is absent or is any value other than the literal string `1`, dispatch shall exit nonzero with a distinct preflight-refusal classification. It shall not claim a slot, create an attempt directory, branch, or worktree, or launch any subprocess containing worker-authored code.

3. **Authorization required in addition to the environment variable.** If isolation is unavailable, `ORCH_ALLOW_UNISOLATED=1` without a valid, unused, invocation-bound single-use token issued by the root-owned helper shall refuse with the same no-state and no-execution guarantees.

4. **Root-backed per-use authorization.** A break-glass token shall be derived from a root-held secret and obtainable only through an explicit interactive `sudo` invocation of a root-owned issuance helper. Issuance shall require fresh interactive authorization and shall not be available through the dispatch process or the scoped noninteractive redemption permission. The authenticated token fields shall cover, at minimum, the exact spec digest, attempt ID, base SHA, and expiry. Any additional token fields, including version, token ID, repository identity, issuer identity, issue time, reason, and exposure acknowledgement, shall also be authenticated. The token shall expire no more than 15 minutes after issuance. Malformed, expired, mismatched, unauthenticated, or otherwise invalid tokens shall fail closed.

5. **Atomic root-owned replay prevention.** Immediately after successful token validation and before `claim_slot`, dispatch shall invoke only the narrowly scoped sudoers redemption helper. The root-owned helper shall atomically validate the token against the root-held secret, compare its authenticated spec digest, attempt ID, base SHA, and expiry with the current invocation, refuse a previously redeemed token, and durably append the redemption to a root-owned append-only ledger before reporting success. The operator UID shall be unable to modify, truncate, replace, unlink, or delete the ledger or its parent directory. A crash after durable redemption shall spend the token rather than make it reusable. Dispatch shall never validate or redeem a token solely in operator-owned code or storage.

6. **Immutable modes.** The only launchable execution modes shall be `ISOLATED` and `UNISOLATED_EXPOSURE`. The selected decision shall be immutable and passed explicitly to `worktree_root`, worker launch, retries, remediation, primary TEST, both regression-gate runs, and every other process-capable consumer found by the implementation inventory.

7. **No recalculation or downgrade.** No consumer other than the preflight selector shall call `isolation_available()` or infer mode independently. Failure, timeout, cleanup error, retry, or remediation transition after selecting `ISOLATED` shall fail the attempt and shall never select or invoke `UNISOLATED_EXPOSURE`.

8. **No false protection claim.** `UNISOLATED_EXPOSURE` shall use the existing same-user behavior without presenting environment scrubbing, namespace probes, credential detection, or other partial controls as a security boundary. Its stderr warning and documentation shall say that worker, TEST, regression, review, retry, and remediation code may access all operator-readable credentials and host state and may communicate over the operator’s available channels.

9. **Break-glass observability.** A launched exposure-mode attempt shall record the mode, attempt ID, non-secret token ID or fingerprint, authenticated issuer identity, reason, issue/expiry timestamps, redemption receipt identifier, and root-owned ledger location in existing launch/evidence metadata. The bearer token, root-held secret, authentication code, and other reusable secret values shall never be added to diagnostics or evidence.

10. **Healthy D5 remains mandatory and preferred.** If isolation is available, dispatch shall select `ISOLATED` even when break-glass variables or a token are present. It shall not redeem the unnecessary token.

11. **Non-vacuous refusal tests.** Every refusal test shall prove that it passed spec validation, reached the intended preflight branch, created no durable attempt state, and launched no worker-controlled payload. Each fixture shall also have a positive control that reaches a launch under either healthy D5 or a valid freshly issued break-glass token.

12. **Two mandatory validation environments.** Release acceptance shall require one report from a real D5-unavailable/userns-restricted environment proving refusal and one report from a real D5-available environment exercising the isolated worker and gate path. A refusal-only result shall be reported as incomplete security validation, not as a full pass.

13. **Non-vacuous live canary drill.** `tests/worker_isolation.sh` shall dynamically resolve the invoking operator’s passwd home, create a harmless disk canary there, and prove the operator can read it. It shall also create a distinct worker-readable control token. Through the same isolated service, probe implementation, executable, argument/path-passing mechanism, and invocation, the worker shall first read and compare the control token successfully and only then attempt to read the exact operator-home canary path. The drill shall require distinct markers for control-read-succeeded, protected-path-attempted, and denial-observed. A missing marker, wrong path, skipped read, failed comparison, missing executable, quoting failure, command failure, service failure, unexpected error classification, or other probe/tool failure is a drill failure and shall never be accepted as isolation confirmation. The drill shall contain no hard-coded `/home/val` and shall clean up reliably.

14. **Current broken state is demonstrated.** A regression test shall fail against commit `995cc13` because the D5-unavailable fixture reaches the same-user launch marker, and shall pass after implementation because dispatch refuses before that marker or durable state exists.

15. **Full validation cannot be skipped.** Missing D5 in the D5-required environment, an unexecuted control read, an unexecuted protected-path attempt, an unavailable required fixture, a probe/tool failure, or an early return shall produce failure or an explicit incomplete result. It shall never be counted as the paired high-assurance validation passing.

16. **Forge, erase, and replay resistance.** A regression shall launch an authorized exposure payload that attempts to mint a lookalike or forged future token, modify or erase its own redemption record, replace or delete the ledger, and replay its spent token. The payload’s ledger mutations shall fail, and every subsequent dispatch using the forged or replayed authorization shall refuse without durable attempt state or worker-controlled execution. Only a fresh token obtained through a new explicit interactive `sudo` issuance may authorize another exposure dispatch.

17. **Root-helper dependency fails closed.** Break-glass depends on the root-owned issuance and redemption helpers and the scoped-sudoers wrapper queued as baton action 5. If any helper, the root-held secret, the root-owned ledger, or the exact scoped-sudoers policy is absent, inaccessible, malformed, or fails validation, break-glass is `UNAVAILABLE`; dispatch shall refuse and shall not substitute an operator-owned file, local MAC check, permissive sudo path, or same-user fallback. Until baton action 5 lands and is installed, PLAN-005 provides refusal only.

## 4. Design / approach

### 4.1 Immutable decision object

Add equivalents of:

```python
class ExecutionMode(Enum):
    ISOLATED = "isolated"
    UNISOLATED_EXPOSURE = "unisolated_exposure"


@dataclass(frozen=True)
class ExecutionDecision:
    mode: ExecutionMode
    isolation_available: bool
    attempt_id: str | None = None
    token_fingerprint: str | None = None
    redemption_receipt_id: str | None = None
```

There is no launchable `AUTO`, `FALLBACK`, or mutable boolean mode. Refusal is an exception/result from preflight, not a mode that downstream code can reinterpret.

`select_execution_decision(...)` is the sole caller of `isolation_available()`:

1. Evaluate D5 availability once.
2. If available, return `ISOLATED`. Ignore and do not redeem an unnecessary break-glass token.
3. If unavailable and the override is not exactly `1`, raise the dedicated preflight refusal.
4. If unavailable and the override is exactly `1`, require the invocation-bound attempt ID and bearer token and atomically redeem them through the root-owned scoped-sudoers helper.
5. Return `UNISOLATED_EXPOSURE` carrying only its non-secret evidence identifiers.

The selector runs before attempt-directory creation and before `claim_slot`.

### 4.2 Root-backed human authorization and redemption

Break-glass requires:

```text
ORCH_ALLOW_UNISOLATED=1
ORCH_UNISOLATED_ATTEMPT_ID=<the exact invocation attempt ID>
ORCH_UNISOLATED_TOKEN=<single-use bearer token printed by the root-owned issuance helper>
```

The token is a separate human action, not something dispatch may synthesize in response to the environment variable. The operator obtains it out-of-band using an explicit interactive invocation equivalent to:

```text
sudo -k /usr/local/libexec/orchestrator-break-glass issue \
  --spec-digest <64-hex digest> \
  --attempt-id <exact invocation attempt ID> \
  --base-sha <40-hex commit> \
  --expires-at <UTC RFC3339> \
  --reason <nonempty operational justification>
```

The installed path and final CLI may follow repository packaging conventions, but the trust properties are mandatory:

- The issuance helper and its parent directory are root-owned and not writable by the operator.
- The helper reads a root-held secret that the operator UID cannot read.
- Issuance requires a controlling terminal and fresh interactive `sudo` authentication; it shall not accept `NOPASSWD`, a cached noninteractive authorization, stdin supplied by dispatch, or invocation by worker-controlled code as equivalent human presence.
- The issuance permission is distinct from the narrow redemption permission.
- The authenticated token envelope contains a version and unique token ID and covers, using a standard keyed construction such as HMAC-SHA-256 over a canonical encoding, the spec digest, attempt ID, base SHA, expiry, and every other asserted field.
- The token includes the exact acknowledgement: `I authorize unisolated execution with full exposure of my credentials and host state for this dispatch.`
- The expiry is no more than 15 minutes after issuance.
- The root-held secret and raw keyed authenticator are never written to repository evidence.

Dispatch treats the token as an opaque bearer value. It does not possess the root secret and cannot mint or independently bless tokens. It passes the opaque token plus the current canonical spec digest, attempt ID, base SHA, and current time to the exact redemption command allowed by the scoped-sudoers wrapper.

The root redemption helper:

1. Opens and locks the root-owned redemption ledger using a root-owned, non-operator-writable path.
2. Parses and authenticates the token using the root-held secret.
3. Requires exact equality between the authenticated and current spec digest, attempt ID, and base SHA.
4. Enforces issue and expiry times and the maximum validity window.
5. Checks the ledger for the unique token ID or equivalent collision-resistant token fingerprint.
6. Refuses if the token was previously redeemed.
7. Appends a complete non-secret redemption record using the helper’s append-only interface and makes it durable with the required flush and filesystem synchronization.
8. Reports success only after durable append, returning a non-secret redemption receipt identifier.
9. Releases the lock.

The check-and-append operation must be serialized as one atomic redemption transaction. Concurrent attempts using one token yield at most one success. A crash before durable append yields no success response. A crash after durable append spends the token even if dispatch never launches.

The ledger and its parent directory are root-owned and configured so the operator UID cannot write, truncate, rename, replace, unlink, or delete them. The scoped helper exposes validation-and-append only; it exposes no delete, rewrite, arbitrary-path, arbitrary-file, secret-export, shell, editor, or general root command. The append-only property must be enforced by root-owned permissions and the helper interface, with any additional host append-only enforcement used by baton action 5 retained rather than weakened.

A consumed token may remain visible to an exposure payload through inherited operator state, but it is no longer a reusable credential: replay is refused by the root ledger. An exposure payload may attempt to invoke redemption and cause denial or consume a separately stolen unspent token, but it cannot mint a valid token without the root secret, erase a redemption, or make a spent token valid again.

This mechanism proves a separate, invocation-bound human action. It does not make same-user execution safe.

Break-glass depends on the scoped-sudoers wrapper queued as baton action 5. Until that wrapper, both root-owned helpers, the root secret, and the protected ledger are installed and validated, break-glass is unavailable. The only implemented behavior in that state is preflight refusal.

### 4.3 Control-flow threading

The selected `ExecutionDecision` becomes a required argument, with no default, for:

- `worktree_root`, replacing its independent call at line 540;
- launch metadata construction near line 717;
- initial worker launch and every retry;
- remediation launches;
- primary TEST;
- both base-overlay and candidate calls in `run_regression_gate`;
- review processes that can execute tools;
- any post-test command identified during inventory that can execute worker-controlled hooks or configuration.

`ISOLATED` always selects the existing `codex-worker`/systemd path. An isolated launch failure is terminal for that attempt.

`UNISOLATED_EXPOSURE` explicitly selects the existing same-user worker and command paths. Those paths must be renamed in diagnostics and internal APIs so they cannot be mistaken for a security fallback. No credential registry or namespace launcher is added.

### 4.4 Refusal behavior

A refusal emits a concise stderr diagnostic containing:

- that D5 isolation is unavailable;
- that no worker-controlled code was launched;
- the D5 recovery action, `scripts/setup-worker-user.sh`;
- that `ORCH_ALLOW_UNISOLATED=1` alone is insufficient;
- that break-glass requires a fresh token from the explicit interactive root-owned issuance helper and atomic redemption through the installed scoped-sudoers helper;
- that if the helpers or policy are absent, break-glass is unavailable and refusal is the only behavior;
- where the per-use human authorization contract is documented.

It must not reveal environment values, bearer tokens, root secret material, authentication codes, or credential contents. Invalid authorization does not create an attempt directory, claim a slot, create Git state, or create a redemption record. A valid token that reaches atomic redemption is spent even if a later local failure prevents attempt creation or launch.

### 4.5 Live isolation canary

Extend `tests/worker_isolation.sh` with a clearly separated live drill:

1. Resolve the operator home from the passwd database for `id -u`; do not trust `$HOME`.
2. Create a uniquely named mode-`0700` temporary directory under that home and a mode-`0600` harmless random protected canary file.
3. Read and compare the protected canary as the operator, proving the positive side.
4. Create a second, distinct random control token at a path deliberately readable by `codex-worker`; verify its ownership, mode, content, and worker readability prerequisites before launch.
5. Launch the actual isolated service as `codex-worker`.
6. Pass both exact paths through the same service invocation and argument/path-passing mechanism to one fixed probe implementation.
7. Before touching the protected canary, have that probe read the control path and compare the bytes with the expected control value. Emit the distinct `CONTROL_READ_SUCCEEDED` marker only after a successful exact comparison.
8. Only after that marker condition is satisfied, emit a distinct `PROTECTED_PATH_ATTEMPTED` marker bound to the exact expected protected-path value or digest, then attempt to read that exact path without printing its contents.
9. Emit `DENIAL_OBSERVED` only for the expected access-denied classification. `ENOENT`, wrong-path results, executable failures, quoting failures, malformed arguments, comparison failures, unexpected exit statuses, missing tools, or service failures are drill failures, not denials.
10. Require all three markers in order and verify that they came from the same service/probe invocation. Fail if the canary was absent, the operator positive read failed, the control read or comparison failed, the protected path differed, the service did not run, or the precise denial result was not observed.
11. Add sabotage regressions that separately skip the control read, break the probe command or executable, and pass a wrong path. Each sabotage must make the drill fail red; none may emit an accepted isolation-confirmed result.
12. Remove both tokens and their temporary directories through an EXIT/interrupt trap and verify cleanup. Cleanup failure fails the drill.

### 4.6 Future hardened-fallback entry bar

Any future plan proposing protected execution without D5 must, before authorization, provide all of:

- A filesystem boundary that excludes operator homes, credential locations, `/run/user/$UID`, host `/proc`, and unrelated writable shared state.
- Pathname Unix-socket and relevant IPC/shared-memory isolation.
- A private, deliberately constructed `/proc` view.
- Descendant lifecycle containment using a PID boundary plus reliable whole-tree kill/cgroup enforcement.
- Direct and indirect network containment.
- Coverage of the worker itself and every TEST, regression, review, retry, remediation, hook-capable, and post-test execution.
- One exact immutable sandbox submode; no payload-time probe ladder or downgrade.
- Representative compatibility probes rather than `/bin/true`.
- Mandatory positive execution in a capable environment plus mandatory refusal in an incapable environment.
- Disk, environment, `/proc`, pathname-socket, network, and double-fork canaries with positive controls.

Credential-file or environment-name discovery may provide warnings but shall not authorize same-user execution.

### 4.7 Alternatives considered

1. **Minimal fail-closed refusal with separately authorized exposure — selected.** It closes the automatic fail-open immediately and makes the emergency exception truthful and auditable without claiming an incomplete sandbox is safe. Authorization crosses a root-owned issuance and redemption boundary unavailable to exposure-mode payloads.

2. **Environment scrub plus user/network namespace.** Rejected. It leaves operator-readable files, pathname sockets, host state, output channels, and descendant lifecycle exposed. The mapped form also fails on the verified primary host.

3. **Credential-registry-based automatic allowance.** Rejected. Credential discovery is incomplete, racy, and unable to prove that arbitrary same-user code lacks access to secrets.

4. **Remove break-glass entirely.** Stronger, but not selected because the governing disposition retains an emergency path. The retained path therefore requires a separate, one-use human authorization, root-secret-derived token, root-owned atomic redemption ledger, and an explicit full-exposure acknowledgement. Until the required privileged infrastructure exists, behavior is equivalent to removing break-glass: dispatch refuses.

5. **Operator-owned authorization files or consumption records.** Rejected. The authorized exposure payload has the operator EUID and can mint files, erase consumption, and replay authorization. Ownership, mode `0600`, symlink checks, and `O_EXCL` under an operator-controlled directory cannot establish human provenance against that payload.

## 5. Affected boundaries & consumers

- **Operator-to-worker trust boundary:** automatic same-user execution is removed. Break-glass crosses this boundary only through explicit exposure acceptance.
- **Preflight-to-durable-state boundary:** refusal must precede attempt-directory creation, `claim_slot`, Git branch/worktree creation, and evidence initialization.
- **Execution-mode contract:** `worktree_root`, launch selection, worker/retry/remediation, TEST, regression, review, and hook-capable post-processing consume the same immutable object.
- **D5 boundary:** existing `codex-worker`, systemd hardening, ACLs, and `/srv/codexwork/worktrees` remain authoritative.
- **Authorization boundary:** issuance uses an explicit interactive `sudo` call to a root-owned helper backed by a root-held secret. Dispatch can request redemption but cannot issue or authenticate tokens itself.
- **Redemption/evidence boundary:** the atomic redemption ledger and its parent are root-owned, append-only through the scoped helper, and unavailable for operator modification or deletion. Only non-secret token fingerprints and redemption receipts cross into operator-owned attempt evidence.
- **Privileged-infrastructure dependency:** the authorization boundary depends on the scoped-sudoers wrapper queued as baton action 5. Before installation, break-glass is unavailable and dispatch only refuses.
- **Test boundary:** deterministic state-machine regressions are necessary but insufficient. Live D5 and D5-unavailable reports form the high-assurance acceptance pair.
- **Canary validity boundary:** an operator-readable protected canary is insufficient by itself. The same live worker probe must first prove its read, compare, command, service, and exact-path transfer path using a worker-readable control token.
- **Documentation boundary:** `CLAUDE.md` and operator-facing diagnostics must describe break-glass as full exposure.
- **Downstream consumers:** attempt manifests, launch metadata readers, integrity hashing, bound review, retries, remediation, and cleanup must tolerate and preserve the new mode and non-secret authorization fields.

No spec-schema change is intended unless implementation exposes mode or authorization as spec input. It should not: break-glass is an operator invocation control, not worker-controlled spec content.

## 6. Ordered implementation steps

1. Re-inventory `scripts/dispatch.py` at HEAD, beginning with the quoted sites at lines 527, 540, 623, 717, 860, and 946. Record every process-capable consumer and the first durable mutation. Stop for plan refresh if the audited topology has materially changed.

2. In `scripts/dispatch.py`, add the frozen execution-mode types, dedicated preflight-refusal result, and the single selector. Place selection after complete spec validation but before attempt-directory creation and `claim_slot`.

3. Define the canonical break-glass request tuple and invocation attempt-ID generation/transfer. Implement only the unprivileged dispatch side: strict opaque-token input handling, exact current-field construction, invocation of the single allowed redemption command, strict receipt parsing, secret redaction, and fail-closed handling. Dispatch shall contain no root secret and no operator-owned fallback validator or ledger.

4. As part of the scoped-sudoers wrapper work queued as baton action 5, install the root-owned interactive issuance helper, root-held secret, root-owned atomic redemption helper, narrowly scoped sudoers rules, and root-owned append-only redemption ledger. Separate interactive issuance authority from noninteractive redemption authority. Until this step lands successfully, leave break-glass unavailable and preserve refusal-only behavior.

5. Change `worktree_root` and launch metadata construction to require the immutable decision. Remove their independent isolation checks.

6. Thread the decision through initial worker launch, retries, remediation, TEST, both `run_regression_gate` executions, review execution, and every additional consumer found in step 1. Remove automatic fallback and make isolated launch failures terminal.

7. Retain the existing same-user mechanics only behind the explicit `UNISOLATED_EXPOSURE` decision. Rename warnings and evidence so the path is never described as isolated, sandboxed, hardened, or credential-safe.

8. Add refusal, token-validation, expiry, mismatch, concurrent redemption, replay, helper-unavailable, single-probe, no-downgrade, and consumer-routing regressions. Add the authorized exposure payload that attempts to forge a token, erase or replace the root ledger, and replay its authorization. Every negative case must include durable-state snapshots, payload markers, exact reason assertions, and a positive control.

9. Extend `tests/worker_isolation.sh` with the dynamic-home protected canary, worker-readable control token, same-service/same-probe ordered reads, three distinct markers, exact denial classification, reliable cleanup, and sabotage cases for skipped read, broken probe command, and wrong path.

10. Update `CLAUDE.md` with the exact token-bearing invocation, interactive issuance command, token bindings, one-use semantics, root-owned ledger, full-exposure warning, recovery guidance, prohibition on persistence, baton-action-5 dependency, and requirement for a fresh human token per use. State explicitly that missing privileged infrastructure makes break-glass unavailable.

11. Add or update evidence-schema handling for `execution_mode`, attempt ID, non-secret token fingerprint, issuer/reason metadata, redemption receipt identifier, and ledger location. Preserve integrity hashing without storing the bearer token or root-secret material.

12. Run deterministic repository tests, then produce the two mandatory environment reports. Do not request authorization based on only one environment.

13. Submit the implementation through the high-assurance lane. The resulting trust-critical PR is never eligible for automatic merge.

## 7. Failure modes & blast radius

| Trigger | Consequence | Required mitigation |
|---|---|---|
| D5 probe returns false | Routine dispatch unavailable | Refuse before state; restore D5. |
| D5 probe falsely returns true | Isolated launch may fail later | Fail the attempt; never downgrade. |
| Probe result changes after preflight | Runtime reality differs from snapshot | Preserve the immutable decision; isolated failure remains terminal. |
| Override is absent, misspelled, or truthy-looking | Emergency launch refused | Accept only literal `1` plus a valid freshly issued token. |
| Token is malformed, stale, mismatched, unauthenticated, or missing | Break-glass refused | No redemption, attempt state, or execution. |
| Root helper, secret, ledger, or scoped-sudoers wrapper is unavailable | Break-glass unavailable | Refuse only; restore or install baton action 5 infrastructure. |
| Authorization is replayed | Repeated exposure without new consent | Atomic root-owned redemption causes refusal. |
| Exposure payload forges operator-owned authorization material | Payload attempts future unauthorized execution | Root-secret authentication rejects it; no operator-owned authorization fallback exists. |
| Exposure payload attempts to erase consumption | Payload tries to make a spent token reusable | Root-owned ledger and parent reject operator modification or deletion; replay still refuses. |
| Concurrent dispatches present one token | More than one exposure might launch | Serialized atomic check-and-append permits at most one success. |
| Crash follows durable redemption | Token is spent without launch | Require a fresh interactive human issuance; safety wins over convenience. |
| A consumer recalculates isolation | Mixed roots or silent downgrade | Required decision argument, call-count regression, and consumer markers. |
| Isolated retry/remediation falls into same-user code | Unauthorized credential exposure | Terminal failure and explicit no-fallback tests. |
| Break-glass is used | Full operator credential and host-state exposure | Prominent warning, root-backed per-use token, evidence, incident-aware operator decision. |
| Evidence omits authorization | Exposure becomes unauditable | Treat attempt as integrity failure. |
| Worker control read never succeeds | Protected denial could be caused by a broken probe | Fail the live drill. |
| Protected-path attempt marker is absent or references the wrong path | Isolation boundary was not exercised | Fail the live drill. |
| Probe reports `ENOENT`, command failure, or other tool error as unreadable | Vacuous green isolation test | Accept only the defined denial classification after successful control read. |
| Canary sabotage remains green | Drill cannot detect a broken probe | Skip-read, broken-command, and wrong-path cases must each fail red. |
| Only the refusal environment is available | Hardened path remains untested | Report validation incomplete; do not authorize. |
| Only the D5 environment is available | Broken-state refusal remains unproven | Report validation incomplete; do not authorize. |
| Canary cleanup fails | Harmless test artifacts remain | Fail visibly and report the exact cleanup targets. |

Worst case if this ships incorrectly: worker-authored code runs as the operator without a valid human authorization and can read or exfiltrate credentials, mutate host state, or persist descendants. Recovery is to stop dispatches, preserve evidence, revoke or rotate potentially exposed credentials, inspect host and repository state, remove persistence, restore D5, revert or repair the dispatcher while it remains paused, and repeat both validation environments. Secret disclosure is irreversible.

A residual availability and denial-of-service risk remains: the operator UID can invoke the narrowly scoped redemption helper and may spend a valid bearer token without completing dispatch, and an authorized exposure payload that obtains an unredeemed token may spend it. This cannot grant additional execution because the root helper cannot be made to mint a new valid token or erase a prior redemption; recovery is a fresh explicit interactive human issuance. The plan deliberately prefers spent authorization and refusal over token reuse.

A deployment dependency also remains: break-glass cannot operate before baton action 5 installs and validates the scoped-sudoers wrapper, root helpers, root-held secret, and protected ledger. The safe interim state is refusal only.

## 8. Validation plan (falsifiable)

### 8.1 Regression that fails on the current state

Using a valid temporary spec and repository fixture:

1. Arrange for the real preflight path to observe D5 as unavailable.
2. Install unique markers for worker, TEST, both regression runs, review, retry, and remediation execution.
3. Snapshot attempt directories, slot state, branches, and worktrees.
4. Invoke the real dispatch entry point without break-glass.
5. Require the dedicated nonzero refusal status and exact decision reason.
6. Require every execution marker to be absent.
7. Require the durable-state snapshot to remain unchanged.
8. Require diagnostics to state that no worker was launched.
9. Run the same valid fixture with healthy isolation and require an isolated launch marker.

Against commit `995cc13`, the unavailable-D5 case fails because it reaches same-user execution. After revision 3 implementation, it passes by refusing before state.

### 8.2 Authorization cases

Mechanically test:

- Literal `1` without a token refuses.
- `true`, `yes`, `01`, whitespace variants, and empty values refuse even with an otherwise valid token.
- Missing root helper, missing root secret, missing ledger, broken ledger ownership/mode, missing exact scoped-sudoers permission, or unexpected helper output makes break-glass unavailable and refuses without launch.
- A token with malformed encoding, invalid authentication, wrong version, wrong spec digest, wrong attempt ID, wrong base SHA, missing acknowledgement, future issue time, expiry, or overlong validity refuses without redemption or launch.
- A token cannot be minted by operator-owned code using arbitrary `authorized_by`, reason, issue time, or binding values.
- A valid freshly issued token plus literal `1` reaches the harmless exposure-mode payload, emits the full-exposure warning, creates exactly one durable root-owned redemption record, and records matching non-secret evidence.
- Reuse of that token refuses and does not launch.
- A crash after durable redemption leaves the token unusable.
- Two concurrent redemptions of the same token produce exactly one successful redemption and at most one launch.
- Healthy D5 selects `ISOLATED` and does not redeem a supplied exposure token.
- The operator UID cannot truncate, modify, rename, replace, unlink, or delete the redemption ledger or its parent.
- The scoped redemption permission cannot run the issuance action, read the root secret, select an arbitrary ledger path, execute a shell, or invoke an arbitrary root command.
- Issuance requires a separate explicit interactive `sudo` invocation and cannot be performed through dispatch or the redemption-only sudo rule.

Every refusal case must assert that the valid spec passed parsing and that removing the targeted defect changes the outcome.

Then run the mandatory hostile-exposure regression:

1. Obtain one fresh token through the real interactive issuance path for a harmless exposure fixture.
2. Launch that authorized exposure payload.
3. From inside the payload, attempt to construct a lookalike future token with chosen spec digest, attempt ID, base SHA, expiry, issuer, and reason.
4. Attempt to truncate, rewrite, rename, replace, unlink, and delete the redemption record, ledger, and ledger parent using the operator EUID.
5. Capture the spent bearer token and attempt to replay it.
6. After the payload exits, invoke dispatch separately with the forged token and with the replayed token.
7. Require every subsequent invocation to refuse before durable attempt state or worker-controlled execution.
8. Verify through the root helper’s read-only audit operation or root-run test fixture that the original redemption remains present exactly once.
9. Obtain a new token through a fresh explicit interactive `sudo` issuance and prove that only this fresh token can authorize the next harmless exposure launch.

### 8.3 Immutable-decision and routing cases

Instrument `isolation_available()` to return alternating values if called more than once. Require:

- Exactly one call per dispatch.
- `worktree_root`, launch metadata, worker, TEST, both regression runs, retry, remediation, and review observe the same decision object.
- An injected isolated-launch failure invokes the isolated launcher first, fails the attempt, and never invokes exposure mode.
- An injected failure in isolated TEST, regression, retry, remediation, or cleanup never recalculates or downgrades.
- Static inspection finds no call to `isolation_available()` outside its definition and the selector.

Positive markers must prove each relevant payload actually ran in the corresponding success case.

### 8.4 Mandatory environment A: D5 unavailable, userns restricted

On a real host/container where D5 is unavailable and unprivileged mapped user namespaces are denied:

1. Record OS, kernel, AppArmor userns setting, repository commit, spec digest, and D5 probe result.
2. Run the valid-spec refusal test through the real entry point.
3. Prove no worker-controlled process or durable attempt state was created.
4. If baton action 5 infrastructure is not installed, prove break-glass reports `UNAVAILABLE`, refuses despite override inputs, and launches no payload. Report break-glass validation as incomplete rather than simulating a helper.
5. Once the real root-owned helpers, root secret, ledger, and scoped-sudoers wrapper are installed, use a disposable, non-secret fixture to issue one token through explicit interactive `sudo` and prove the harmless positive-control payload launches only with all required invocation-bound inputs.
6. Run the forge/erase/replay hostile-exposure regression and prove that every later dispatch refuses until a fresh human token is issued.
7. Prove mapped `unshare` denial only as host background evidence; dispatch must not call `unshare`.

This environment proves fail-closed behavior. It does not prove D5 isolation. Before baton action 5 lands, its valid result is refusal-only and the overall high-assurance release validation remains incomplete for break-glass.

### 8.5 Mandatory environment B: D5 available

On a host with the real worker account, ACLs, worktree root, sudo policy, and hardened systemd services:

1. Record the same host and commit metadata plus successful D5 preflight.
2. Dispatch a harmless valid fixture through the real isolated worker path.
3. Prove the worker, primary TEST, and both regression runs execute as `codex-worker` in their expected services and worktree location.
4. Inject an isolated launch failure and prove no same-user process runs.
5. Run `tests/worker_isolation.sh` and require the dynamic-home canary drill to execute fully.
6. Prove the operator can read and compare the protected canary.
7. Prove the same isolated service and probe receive both exact paths, read and compare the worker-readable control token first, and emit `CONTROL_READ_SUCCEEDED`.
8. Prove the same probe then emits `PROTECTED_PATH_ATTEMPTED` for the exact operator-home canary path and receives the accepted access-denied classification.
9. Require the distinct `DENIAL_OBSERVED` marker only after the protected attempt and require all three markers in order from the same invocation.
10. Run the skip-read, broken-probe-command, and wrong-path sabotage cases separately and require each drill invocation to fail red.
11. Require cleanup of both tokens and absence of hard-coded `/home/val`.

This environment proves the intended boundary actually executes and that the protected-path denial is not an artifact of a broken worker probe.

### 8.6 Canary probe result contract

The live probe shall return structured results that distinguish these states:

- `CONTROL_READ_SUCCEEDED`: the exact worker-readable control path was opened, read, and byte-compared successfully.
- `PROTECTED_PATH_ATTEMPTED`: emitted immediately before opening the exact protected canary path, with an exact path value or collision-resistant path digest that the harness verifies.
- `DENIAL_OBSERVED`: the exact protected path returned the expected permission-denied classification.
- `PROBE_FAILURE`: any failure to execute the probe, parse arguments, transfer either exact path, read or compare the control, locate a required tool, emit ordered markers, or classify the protected result.
- `BOUNDARY_FAILURE`: the protected canary was read successfully or otherwise became accessible.

Only the ordered sequence `CONTROL_READ_SUCCEEDED` → `PROTECTED_PATH_ATTEMPTED` → `DENIAL_OBSERVED` passes. `PROBE_FAILURE`, `BOUNDARY_FAILURE`, missing output, timeout, service failure, `ENOENT`, and unexpected error codes fail the drill.

Sabotage validation shall demonstrate:

- A probe variant that skips the actual control-file read cannot pass by printing the marker.
- A nonexistent or deliberately broken probe command fails as `PROBE_FAILURE`.
- Substituting a wrong control or protected path fails exact-path or content verification and cannot be accepted as denial.

### 8.7 Completion rule

Produce one machine-readable report from each environment, bound to the same implementation commit and test digest. The high-assurance validation is complete only when both reports pass, the real privileged break-glass infrastructure has passed the authorization and hostile-exposure cases, and the live canary’s three-marker positive control and sabotage cases pass. A single refusal report, a simulated root helper, a simulated isolated result, an early success, a skipped worker control read, or a skipped live canary is explicitly `INCOMPLETE`, never `PASS`.

Run, at minimum:

```text
python3 -m py_compile scripts/dispatch.py
./tests/isolation_fail_closed.sh
./tests/worker_isolation.sh
./scripts/test
```

Any environment-specific prerequisite failure must be reported against the corresponding mandatory report; it cannot be converted into a full-suite success.

## 9. Rollback / irreversibility

There is no data migration. The authorization and evidence fields are additive. Root-owned redemption entries are append-only audit records and are not rolled back or deleted.

To roll back an implementation defect:

1. Stop all new dispatches.
2. Preserve attempt, token-issuance, redemption-ledger, and validation evidence.
3. Restore and verify D5.
4. Disable the scoped redemption permission if the privileged helper is implicated; do not weaken or erase the ledger.
5. Revert the implementation only while dispatch remains administratively paused.
6. Correct the fail-closed implementation and repeat both mandatory environments before resuming.

Rollback must never restore automatic same-user fallback or replace the root-backed mechanism with operator-owned authorization files. The safe degraded state is “dispatcher unavailable.”

Break-glass exposure is irreversible if code observes or copies a credential. After any suspicious use, treat credentials and host state as potentially compromised and follow the recovery procedure in section 7.

A spent token remains spent across rollback. If the helper or ledger state cannot be trusted, disable break-glass and refuse until the root-owned infrastructure is repaired and independently validated.

## 10. Open questions / operator decisions

None. Claude’s disposition establishes the governing choices: minimal fail-closed refusal, root-secret-derived single-use break-glass tokens obtained through explicit interactive `sudo`, atomic root-owned append-only redemption through the scoped-sudoers helper, paired non-vacuous validation, and the worker-side positive-control canary drill.

Each future break-glass use still requires its own fresh human token; that is an operational authorization, not an unresolved design question.

The dependency on baton action 5 is also resolved rather than open-ended: until the scoped-sudoers wrapper and root-owned helper infrastructure land, break-glass is unavailable and dispatch refuses.

## 11. Provenance (filled during challenge/authorization — NOT by the drafter)

- **Challenge (Claude):** Revision 2 received `BLOCK` with exactly two findings: operator-owned authorization/replay state collapsed after one exposure, and the live canary lacked a worker-side positive control.
- **Disposition (drafter):** Both revision 2 findings were sustained with Claude’s chosen mechanisms and applied in revision 3. All other revision 2 design elements remain frozen.
- **Dual-validation (high-assurance/control-plane):** Prior fresh-context SOL design review: `BLOCK`, one round. Revision 3 SOL and Claude verdicts pending.
- **Authorization:** Pending. No digest has been authorized; silent edits after authorization will void it.
- **Completion reconciliation:** Pending implementation.

## Disposition record (revision 3)

1. **Finding 1 — sustained-applied.** Sections 1, 2, 3.3–3.5, 3.9–3.11, 3.16–3.17, 4.1–4.2, 4.4, 4.7, 5, 6.3–6.4, 6.8, 6.10–6.11, 7, 8.2, 8.4, 8.7, 9, and 10 replace operator-owned artifacts and consumption files with single-use tokens derived from a root-held secret, obtained out-of-band through explicit interactive `sudo`, and atomically redeemed through the scoped-sudoers helper into a root-owned append-only ledger the operator UID cannot modify or delete. Token authentication covers the spec digest, attempt ID, base SHA, and expiry; replay is refused. The hostile authorized payload now attempts token forgery, ledger erasure, and replay, and every subsequent dispatch must refuse without a fresh human token. The dependency on baton action 5 is explicit: until its wrapper and root helpers are installed, break-glass is unavailable and dispatch provides refusal only.

2. **Finding 2 — sustained-applied.** Sections 3.13, 3.15, 4.5, 5, 6.9, 7, and 8.5–8.7 add a distinct worker-readable control token that the same isolated service, probe implementation, executable, and path-passing mechanism must read and compare successfully before attempting the operator-home canary. The drill requires ordered, distinct `CONTROL_READ_SUCCEEDED`, `PROTECTED_PATH_ATTEMPTED`, and `DENIAL_OBSERVED` markers; probe, tool, quoting, path-transfer, `ENOENT`, and service failures fail the drill rather than confirming isolation. Skip-read, broken-command, and wrong-path sabotage cases must each fail red.
