# BorgBar — Product Requirements Document

## Overview

BorgBar is a macOS menubar application that provides a Time Machine-like backup experience for [BorgBackup](https://www.borgbackup.org/). It runs scheduled backups from APFS snapshots, shows backup status in the menubar, and handles backup orchestration directly in the app.

Restores are out of scope for MVP and are done via borg CLI.

## Problem Statement

BorgBackup is fast and efficient, but operationally it is CLI-heavy. Users currently need to build their own scripts for scheduling, snapshotting, and monitoring. BorgBar provides a native macOS control plane for these tasks.

## Goals

- Zero/low-configuration path for a single remote repository over SSH
- APFS snapshot-based backups for consistency (non-negotiable)
- Menubar-native UX for status, progress, and manual trigger
- Reliable background operation with low idle footprint

## Non-Goals (MVP)

- Full system/bare-metal backup
- Building a backup engine (we orchestrate borg)
- In-app restore UI
- SSH password authentication (keys only)
- Managing `~/.ssh/config` (never)
- App Store distribution
- Multi-repo orchestration
- Parallel backups

---

## Distribution & Platform

### Distribution

- Direct distribution via GitHub Releases (`.app`)
- Code signing and notarization are required for release builds
- “Signed releases later” is acceptable during early local development

### Platform Requirements

- macOS 14 Sonoma or later
- APFS volume
- BorgBackup (latest stable) installed via Homebrew
- SSH access to remote repository (if repository is remote)

---

## Architecture

### Core Components

- **Menubar app (SwiftUI/AppKit bridge)**
  - Status icon/state
  - Popover UI
  - Settings and setup wizard

- **Backup Orchestrator (app process or XPC service)**
  - Owns backup state machine
  - Launches borg subprocesses
  - Parses JSON/log output into UI events
  - Persists run history

- **Privileged Helper (root, XPC)**
  - Installed via `SMJobBless`
  - Handles APFS snapshot create/mount/cleanup only
  - Strictly limited API surface

### Dependencies

- **Required**: `borg`
- **Not used**: `borgmatic`
- **APFS snapshot tooling**: helper wraps system-level snapshot/mount operations

### Trust Boundaries

- Main app runs as user
- Helper runs as root and only accepts XPC requests from signed main app
- Secrets stay in macOS Keychain

---

## MVP Scope

### Included

1. Single repository setup and management
2. APFS snapshot-based backup pipeline
3. Schedule: one daily time + manual “Back Up Now”
4. Optional wake scheduling for daily backup (narrow mode)
5. Menubar states and progress phases
6. Stop/cancel backup
7. Basic notifications (success/failure)
8. Structured logs and local history

### Explicitly Deferred

- Multiple repositories
- Advanced network policy engine (SSID/tethering classification)
- Quota auto-remediation loops
- In-app restore browser
- Bandwidth throttling UI
- iCloud settings sync

---

## Backup Pipeline (Authoritative)

For each scheduled/manual run:

1. **Preflight**
   - Validate `borg` path
   - Validate repository config and key path
   - Validate Keychain passphrase item exists
   - Optional reachability probe for remote repo

2. **Create snapshot** (privileged helper)

3. **Mount snapshot read-only** (privileged helper)

4. **Create archive**
   - Run `borg create` against snapshot mount
   - Use required flags and exclusions merged from 3 sources:
     - user list (`userExcludePatterns` and `userExcludeDirectoryContents`)
     - common-sense list (`commonSenseExcludePatterns`)
     - Time Machine-derived list (`timeMachineExcludedPaths`)
   - Stream progress/log events to UI

5. **Retention maintenance**
   - Run `borg prune`
   - Run `borg compact`

6. **Cleanup** (always attempted)
   - Unmount snapshot
   - Delete snapshot

7. **Persist results**
   - Run stats, outcome, duration, error reason (if any)
   - Write history entry and logs

### Failure Semantics

- Snapshot create/mount failure: run fails
- `borg create` failure: run fails
- `prune`/`compact` failure after successful create: run is marked **Success with maintenance warning**
- Cleanup is best-effort but always executed

### Exclusion Refresh Semantics

- On app startup, before any backup is started, compare current macOS version to `timeMachineExclusionOSVersion`.
- If changed (or missing), immediately re-scan all relevant directories under `includePaths` with `tmutil isexcluded`.
- Persist paths that Time Machine excludes into `timeMachineExcludedPaths`.
- No backward compatibility is required for older exclusion schema keys.

---

## Privileged Helper Contract

### XPC Interface (MVP)

- `createSnapshot(volume: String) -> SnapshotRef`
- `mountSnapshot(snapshot: SnapshotRef) -> MountRef`
- `unmountSnapshot(mount: MountRef)`
- `deleteSnapshot(snapshot: SnapshotRef)`
- `cleanupStaleSnapshots(prefix: String)`

### Constraints

- Helper only performs APFS snapshot/mount lifecycle operations
- No network operations
- No SSH/keychain logic
- Caller signature validation is mandatory

---

## Scheduling

### Baseline (MVP)

- Daily schedule at user-selected local time
- Manual run from menubar
- Missed-run catch-up: run once when app next becomes eligible

### Wake Scheduling (MVP Optional)

If enabled:
- Register one daily wake event
- Only wake when on AC power
- Respect user toggle and backup window

If implementation risk grows, wake scheduling may ship in v1.1 without changing the rest of MVP.

---

## Configuration Storage

### App Config

Stored at:
`~/Library/Application Support/BorgBar/app-config.json`

```json
{
  "version": 3,
  "repo": {
    "id": "nas-main",
    "name": "NAS Backup",
    "path": "ssh://user@host/path",
    "sshKeyPath": "~/.ssh/borgbar_nas_ed25519",
    "compression": "zstd,3",
    "includePaths": ["/Users/da"],
    "userExcludePatterns": [
      "*/venv/*"
    ],
    "commonSenseExcludePatterns": [
      "*/Caches/*",
      "*/.Trash/*",
      "*/node_modules/*",
      "*/.build/*",
      "*/DerivedData/*",
      "*/.DS_Store",
      "*/nobackup/*"
    ],
    "userExcludeDirectoryContents": [
      "~/Downloads"
    ],
    "timeMachineExcludedPaths": [
      "/Users/da/Library/Caches"
    ],
    "timeMachineExclusionOSVersion": "15.3.2",
    "timeMachineExclusionScannedAt": "2026-02-28T10:00:00Z",
    "retention": {
      "keepHourly": 24,
      "keepDaily": 7,
      "keepWeekly": 4,
      "keepMonthly": 6
    }
  },
  "schedule": {
    "dailyTime": "03:00",
    "wakeEnabled": false
  },
  "preferences": {
    "notifications": "all",
    "reachabilityProbe": true
  },
  "paths": {
    "borgPath": "/opt/homebrew/bin/borg"
  }
}
```

### History

Stored at:
`~/Library/Application Support/BorgBar/history.json`

Contains one entry per run:
- start/end time
- outcome (`success`, `success_with_warning`, `failed`)
- phase that failed
- bytes/files/stats
- error summary

### Logs

Stored at:
`~/Library/Logs/BorgBar/`

Per-run structured logs + borg stdout/stderr capture, with rotation.

---

## Secrets & Authentication

- SSH keys only (no passwords)
- App never edits `~/.ssh/config`
- Repo passphrase stored in Keychain per repo id
- Passphrase provided to borg via `BORG_PASSCOMMAND`
- Optional repo key export flow can be added later; not required for MVP

### Borg Invocation Contract (MVP)

Environment:
- `BORG_RSH="ssh -i <key> -o IdentitiesOnly=yes"`
- `BORG_PASSCOMMAND="security find-generic-password -a BorgBar -s borgbar-repo-<repo-id> -w"`

Required create behavior:
- Preserve xattrs, ACLs, flags
- Use checkpoint interval
- Use configured compression

---

## Menubar UX (MVP)

### States

- Idle
- Preflight
- Creating snapshot
- Uploading (`borg create`)
- Pruning
- Compacting
- Cleaning up
- Waiting (scheduled)
- Error

### Popover Content

Idle:
- Last backup time + outcome
- Last run summary stats
- Next scheduled time
- `Back Up Now`

Running:
- Current phase
- Progress text from borg output
- Elapsed time
- `Stop Backup`

Error:
- Human-readable failure reason
- `Open Logs`
- `Try Again`

---

## Error Handling Policy (MVP)

- Retry once for transient network/preflight issues
- On lock-related errors: optional one-time `borg break-lock` retry, then fail
- On user stop:
  1. Send `SIGTERM` to active borg process
  2. Wait up to 10s
  3. Send `SIGKILL` if needed
  4. Cleanup snapshot lifecycle
  5. Record run as cancelled

Principle: always prefer safe cleanup and clear state over aggressive automation.

---

## Testing Strategy (MVP)

- Unit tests for state machine transitions and failure mapping
- Integration tests for subprocess wrapper (mocked borg output)
- Manual end-to-end matrix:
  - Local repo success
  - Remote repo success
  - Interrupted network
  - Bad passphrase
  - Missing key
  - Snapshot failure path
  - Cancel mid-run

---

## Open Questions

1. Which exact snapshot command set should helper use for best compatibility (`tmutil`-driven vs lower-level APFS tooling)?
2. Whether wake scheduling is in v1.0 or v1.1, based on implementation effort after helper stabilization.
3. Whether to include one-time recovery-key export UX in MVP or defer.
