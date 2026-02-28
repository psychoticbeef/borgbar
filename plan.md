# BorgBar MVP Implementation Plan

This plan translates the PRD into executable milestones with acceptance criteria.

## Milestone 0: Project Foundation

### Tasks

- Create macOS menubar app skeleton (SwiftUI + status item/popover).
- Define module boundaries:
  - `AppUI`
  - `Core` (models/config/state)
  - `Orchestrator` (backup runner)
  - `HelperClient` (XPC client)
  - `PrivilegedHelper` (XPC server)
- Add structured logging baseline.
- Add app data directories bootstrap:
  - `~/Library/Application Support/BorgBar/`
  - `~/Library/Logs/BorgBar/`

### Acceptance Criteria

- App launches as menubar-only app.
- Popover opens and displays placeholder status.
- Log file is written on launch.
- Required directories are created automatically.

---

## Milestone 1: Config + Secrets

### Tasks

- Implement `app-config.json` schema and load/save service.
- Implement config validation on startup.
- Build setup UI for single repository:
  - Name
  - Repo path
  - SSH key path
  - Include paths
  - Exclude patterns
  - Retention policy
  - Daily schedule time
- Implement Keychain integration for repo passphrase item:
  - Create/update/read/delete by repo id
- Implement preflight checks:
  - borg binary exists
  - key file exists/readable
  - keychain passphrase item exists

### Acceptance Criteria

- Config persists and reloads across relaunch.
- Invalid config is rejected with actionable UI error.
- Repo passphrase is never written to config/log files.
- Preflight errors are surfaced in UI before a run starts.

---

## Milestone 2: Privileged Helper (Snapshot Lifecycle)

### Tasks

- Create privileged helper target (root daemon via `SMJobBless`).
- Define XPC protocol:
  - `createSnapshot(volume:)`
  - `mountSnapshot(snapshot:)`
  - `unmountSnapshot(mount:)`
  - `deleteSnapshot(snapshot:)`
  - `cleanupStaleSnapshots(prefix:)`
- Implement helper-side caller signature validation.
- Implement helper operations for APFS snapshot/mount/unmount/delete.
- Implement app-side `HelperClient` with request/response mapping and timeout handling.
- Run stale snapshot cleanup on app launch.

### Acceptance Criteria

- Helper installation flow works on a clean machine.
- App can create, mount, unmount, and delete snapshot through helper.
- Unauthorized caller is rejected by helper.
- Stale BorgBar snapshots are cleaned up on launch.

---

## Milestone 3: Backup Orchestrator State Machine

### Tasks

- Implement run state machine:
  - `idle`
  - `preflight`
  - `creatingSnapshot`
  - `mountingSnapshot`
  - `creatingArchive`
  - `pruning`
  - `compacting`
  - `cleanup`
  - `success`
  - `successWithWarning`
  - `failed`
  - `cancelled`
- Enforce single active run.
- Implement cancellation behavior:
  - SIGTERM -> wait 10s -> SIGKILL
  - always execute cleanup path
- Persist run result (status/phase/error/duration).

### Acceptance Criteria

- State transitions are deterministic and logged.
- Only one run can execute at a time.
- Cancel during `borg create` correctly terminates process and cleans snapshot.
- Final run state is always emitted and persisted.

---

## Milestone 4: Borg Command Runner

### Tasks

- Implement subprocess wrapper for borg commands.
- Wire required environment variables:
  - `BORG_RSH="ssh -i <key> -o IdentitiesOnly=yes"`
  - `BORG_PASSCOMMAND=...security find-generic-password...`
- Implement command execution sequence:
  - `borg create`
  - `borg prune`
  - `borg compact`
- Parse output for:
  - phase status
  - file/progress lines (best effort)
  - summary stats
- Add retry policy:
  - one retry for transient preflight/network failures
  - optional one-time lock recovery (`borg break-lock`) then retry

### Acceptance Criteria

- Successful run produces archive + prune + compact sequence.
- `create` failure marks run failed.
- `prune`/`compact` failure after successful create marks `successWithWarning`.
- Lock recovery path runs at most once per run.

---

## Milestone 5: Menubar UX

### Tasks

- Implement icon/status mapping for runtime phases.
- Implement popover sections:
  - idle summary
  - active run view
  - error view
- Add controls:
  - `Back Up Now`
  - `Stop Backup`
  - `Open Logs`
  - `Try Again`
- Display last run timestamp/outcome/stats.
- Add lightweight animation only for active phases.

### Acceptance Criteria

- UI updates live with orchestrator state changes.
- Buttons trigger expected actions reliably.
- Error reason is human-readable and actionable.
- UI remains responsive during long backups.

---

## Milestone 6: Scheduling

### Tasks

- Implement daily local-time scheduler.
- Implement missed-run catch-up (coalesced: one catch-up run).
- Gate scheduled run on active-run lock and preflight eligibility.
- Add schedule preferences UI.

### Acceptance Criteria

- Scheduled run starts at configured time.
- Missed scheduled run executes once when eligible.
- Scheduler never launches concurrent runs.

---

## Milestone 7: Notifications, History, and Logs

### Tasks

- Implement success/failure notifications.
- Implement `history.json` writer/reader with rolling retention.
- Persist per-run:
  - timestamps
  - duration
  - result
  - failed phase
  - summary stats
- Add "Open Logs" behavior to reveal log location.

### Acceptance Criteria

- User receives notification on run completion/failure.
- History survives restart and is queryable by UI.
- Logs are rotated and correlated with run ids.

---

## Milestone 8: Wake Scheduling (Optional MVP)

### Tasks

- Add wake toggle in settings.
- Register one daily wake event.
- Restrict wake scheduling to AC power mode.
- Ensure wake schedule updates when user changes schedule.

### Acceptance Criteria

- Wake event is registered and visible in system scheduling state.
- Backup starts after wake when eligible.
- Wake scheduling can be disabled cleanly.

---

## Quality Gates

## Automated

- Unit tests for config validation.
- Unit tests for state machine transitions.
- Unit tests for error-to-user-message mapping.
- Integration tests for borg runner with mocked outputs.

## Manual E2E Matrix

- Local repository full success path.
- Remote repository full success path.
- Missing borg binary.
- Missing SSH key.
- Bad passphrase.
- Snapshot create failure.
- Network interruption during create.
- User cancel during create.
- Lock error recovery path.

### Release Readiness Criteria

- No data-loss bug in cancellation/cleanup paths.
- Snapshot lifecycle is leak-free across crash/restart tests.
- At least 10 consecutive scheduled runs complete in test environment without manual intervention.
- Logs and history are sufficient to diagnose failures without attaching debugger.

---

## Suggested Build Order

1. Milestones 0-1
2. Milestone 3 (state machine shell with fake runner)
3. Milestone 2 (helper)
4. Milestone 4 (real borg runner)
5. Milestones 5-7
6. Milestone 8 (optional)

---

## Out-of-Scope for This Plan

- Multi-repo support
- SSH config file management
- App Store packaging
- Restore UI
- Advanced network policy system

