# Review 001

Scope: Milestones 0-7 implementation pass (single-repo MVP app path)

## Reviewer 1 (Correctness)

Findings:

- **[P1] Catch-up scheduler triggered repeatedly after scheduled minute**
  - Risk: multiple unintended daily runs.
  - Fix: changed scheduler to trigger at most once per day using `lastTriggeredDay`.
  - Status: Closed.

- **[P1] Snapshot deletion used snapshot label rather than `tmutil` snapshot date token**
  - Risk: stale snapshots left behind.
  - Fix: `SnapshotRef` now stores `snapshotDate`; deletion calls `tmutil deletelocalsnapshots <snapshotDate>`.
  - Status: Closed.

- **[P2] Lock recovery path missing**
  - Risk: recoverable repository lock errors failed hard.
  - Fix: orchestrator now retries once with `borg break-lock` on lock-related create failure.
  - Status: Closed.

## Reviewer 2 (Reliability/Security)

Findings:

- **[P1] Concurrency safety issue in shared logger singleton type**
  - Risk: Swift 6 compile/runtime race diagnostics.
  - Fix: replaced mutable singleton class with static enum logger API.
  - Status: Closed.

- **[P2] Privileged helper integration not complete yet**
  - Risk: snapshot flow currently uses local command path, not helper boundary.
  - Fix in this pass: added `HelperSnapshotService` contract/stub and retained `SnapshotService` abstraction.
  - Status: Open (Milestone 2 remaining).

## Gate Result

- Open P0: 0
- Open P1: 0
- Open P2+: 1 (tracked, non-blocking for current pass)

Result: Pass for current slice set.

