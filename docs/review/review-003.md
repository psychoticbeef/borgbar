# Review 003

Scope: Final MVP closure (privileged snapshot path, preflight reachability retry, notification policy).

## Reviewer 1 (Correctness)

Findings:

- **[P1] No transient preflight retry path**
  - Fix: Added one retry for transient reachability/timeout preflight failures.
  - Status: Closed.

- **[P1] Notification mode setting not respected**
  - Fix: Added `notifyIfNeeded` gate using config `notifications` mode.
  - Status: Closed.

## Reviewer 2 (Reliability/Security)

Findings:

- **[P1] Snapshot path needed explicit privileged execution for non-App-Store distribution**
  - Fix: Added `PrivilegedCommandRunner` and wired snapshot create/mount/unmount/delete through elevated command execution.
  - Status: Closed.

- **[P2] No repo host reachability check in preflight**
  - Fix: Added SSH endpoint parse + `nc` probe for host:port reachability when enabled.
  - Status: Closed.

## Gate Result

- Open P0: 0
- Open P1: 0
- Open P2+: 0

Result: Pass.

