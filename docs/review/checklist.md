# Review Checklist (Mandatory)

Use this checklist in every review cycle.

## Correctness

- Does the change satisfy the exact acceptance criteria for the ticket?
- Are state transitions valid and exhaustive?
- Are terminal states always persisted?
- Is cancellation deterministic and idempotent?

## Snapshot Safety

- Is snapshot cleanup attempted in all failure/cancel paths?
- Are mount/unmount operations balanced?
- Are stale snapshots handled safely?

## Security

- Any possibility of command injection in borg/ssh invocation?
- Are secrets excluded from logs and config writes?
- Is Keychain access scoped and minimal?
- Does privileged helper validate caller identity?

## Reliability

- Timeouts present for XPC and subprocess calls?
- Retries bounded (no infinite loops)?
- User-facing errors actionable and phase-specific?

## Regressions

- Existing tests still pass?
- New tests added for changed behavior?
- Manual verification steps documented?

## Policy

- No `borgmatic` reintroduced.
- No edits to `~/.ssh/config`.
- No unresolved P0/P1 findings before merge.

