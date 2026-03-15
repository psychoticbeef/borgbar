# BorgBar User Stories

## Product Context

BorgBar is a macOS menubar backup orchestrator for BorgBackup. It is focused on single-user operation and provides a native control plane for running consistent backups from APFS snapshots.

The product intent is to replace ad-hoc backup scripting with a reliable, observable, and permission-aware app workflow. BorgBar coordinates preflight checks, snapshot lifecycle, Borg archive and maintenance commands, scheduling, notifications, and operational recovery paths.

BorgBar is not a new backup engine. It orchestrates existing system and Borg tooling with clear trust boundaries: the main app runs as the user, secrets are stored in Keychain, and a tightly scoped privileged helper is used only for allowlisted elevated commands.

## Product Goals

- Deliver a low-friction, menubar-native backup experience for Borg on macOS.
- Enforce snapshot-based consistency and avoid silent fallback to live filesystem backup behavior.
- Provide safe automation through daily scheduling, retry logic, and optional wake coordination.
- Surface actionable diagnostics for permissions, helper health, command failures, and runtime warnings.
- Preserve user control and transparency through explicit configuration, logs, history, and settings.

## Technology Choices

- Platform: macOS 26+ on APFS.
- Language and build stack: Swift 6.2 with Xcode app targets and Swift Package Manager modules.
- UI stack: SwiftUI.
- Backup engine: BorgBackup CLI (`borg`) orchestrated directly by BorgBar.
- Privileged operations: XPC-based helper service with allowlisted command execution.
- System command surface: `tmutil`, `mount_apfs`, `umount`, `pmset`, `nc`, and related host tools.
- Secret storage: macOS Keychain (`Security` framework).
- Persistence format: JSON config/history/state in Application Support.
- Logging and telemetry: `OSLog` + local log files; optional Healthchecks integration via `URLSession`.
- Notifications: macOS local notifications through `UserNotifications`.
- Startup/login integration: `SMAppService` for launch-at-login and helper registration flow.

## Code Quality Methodology

This is the working code-quality approach used for BorgBar implementation:

- Warnings are treated as errors in integration workflows; no warning debt is accepted silently.
- Static analysis: use Periphery to find/remove dead code and JSCPD to identify/refactor duplication hotspots.
- Coverage focus: drive very high branch coverage.

## Cross-Cutting Concepts (Implemented + Discussion Decisions)

- Snapshot-first invariant: backups run from APFS snapshots only; no silent fallback to live filesystem backup.
- Retry-window snapshot policy: failed/cancelled runs preserve reusable snapshots and retry until the next scheduled backup window, then clean up.
- Single orchestration model: manual, scheduled, and retry runs share one pipeline/state machine and one-active-run semantics.
- Warning semantics over false failure: successful archive creation with maintenance issues is recorded as success-with-warning, not hard failure.
- Least-privilege boundary: privileged helper is restricted to an allowlisted command surface; app logic, secrets, and network stay outside helper scope.
- One-time privilege UX target: avoid repeated password prompts; use helper approval/install flow through app UX, with actionable remediation.
- Permission-first gating: FDA and helper-health states are checked early and surfaced consistently before sensitive operations proceed.
- Fail-safe + observable behavior: explicit phase/status/log/history signals are required so users can see what happened and why.
- Non-blocking integrations: external monitoring (Healthchecks) and notifications must never block or fail the core backup pipeline.
- Config/secret ownership split: JSON stores operational config; Keychain stores sensitive material; no secret spill into config/history logs.
- User-control invariant from thread decisions: avoid hidden destructive behavior (for example, surprise restarts or implicit data-destructive actions).

## EPIC 1: Product Shell & App Lifecycle

- US-E1-01: As a user, I want BorgBar to run as a single menubar accessory app so backup control stays lightweight and unobtrusive.
- US-E1-02: As a user, I want the popover to open focused with clear current-state badges so I can act immediately without extra clicks.
- US-E1-03: As a user, I want duplicate app instances terminated automatically so only one backup controller is active.
- US-E1-04: As a user, I want safe quit behavior that handles idle, in-progress termination, active-backup confirmation, and force-quit fallback so I can exit without corrupting active work.
- US-E1-05: As a user, I want quick controls in the menubar surface (Back Up Now, Stop, Settings, Logs, Quit) so core actions are always one step away.

## EPIC 2: Backup Pipeline & Orchestration

- US-E2-01: As a user, I want one orchestrator to run manual, scheduled, and retry-triggered backups with a single-active-run guarantee so execution is deterministic.
- US-E2-02: As a user, I want each run to execute a consistent phase pipeline (preflight, snapshot, archive, prune, compact, cleanup, persist) so behavior is predictable.
- US-E2-03: As a user, I want cancellation to terminate active process trees and transition run state cleanly so stop actions are immediate and safe.
- US-E2-04: As a user, I want archive creation to support lock recovery (`break-lock`) and warning-aware exit handling so recoverable errors do not require manual intervention.
- US-E2-05: As a user, I want prune/compact/repository-size issues captured as warnings when archive creation succeeds so successful backups are not mislabeled as hard failures.
- US-E2-06: As a user, I want repository over-target analysis with oldest-archive trim suggestions so storage pressure has actionable remediation.
- US-E2-07: As a user, I want subprocess execution with streaming lines, full stdout/stderr capture, timeouts, environment overlays, and forced descendant cleanup so command execution is robust.
- US-E2-08: As a user, I want sleep assertions held for active backups so long operations are less likely to be interrupted.

## EPIC 3: Snapshot Lifecycle & Filesystem Consistency

- US-E3-01: As a user, I want backups to run from APFS snapshots mounted into dedicated temporary mountpoints so source data is consistent.
- US-E3-02: As a user, I want snapshot creation to fail fast when no valid snapshot date can be confirmed so backup integrity is enforced.
- US-E3-03: As a user, I want snapshot mount attempts to try bounded retries across source and option variants so transient mount issues can self-recover.
- US-E3-04: As a user, I want mount failures classified into actionable guidance (for example FDA remediation or resource-busy retry/reboot advice) so recovery is clear.
- US-E3-05: As a user, I want failed or cancelled runs to preserve reusable local snapshots until cutoff so retries can resume from the same point-in-time state.
- US-E3-06: As a user, I want successful runs to delete local snapshots according to reuse-window policy so retention is controlled.
- US-E3-07: As a user, I want stale snapshot mount directories and expired/missing reuse state cleaned automatically on startup so interrupted runs do not leak resources.

## EPIC 4: Scheduling, Retry & Wake Automation

- US-E4-01: As a user, I want a daily scheduler that triggers at configured local time, only once per day, and only when no backup is already running.
- US-E4-02: As a user, I want delayed failure retries that run within a bounded window before the next scheduled backup so transient errors recover without runaway retries.
- US-E4-03: As a user, I want retry jobs cancelled when superseded, cutoff-expired, or blocked by active runs so stale retries do not fire unexpectedly.
- US-E4-04: As a user, I want wake scheduling to compute and program one-shot wakes from daily backup time so sleeping machines can still run backups.
- US-E4-05: As a user, I want legacy repeating wake schedules detected and removed so old and new wake models do not conflict.
- US-E4-06: As a user, I want wake scheduling failures (invalid times, pmset errors) surfaced with actionable diagnostics so automation can be corrected quickly.
- US-E4-07: As a user, I want wake schedule and retry policy refreshed after startup and run completion so automation state stays aligned with config.

## EPIC 5: Configuration, Persistence & Exclusion Data

- US-E5-01: As a user, I want a versioned app config model for repository, schedule, preferences, and paths so backup behavior is explicit and durable.
- US-E5-02: As a user, I want default config creation plus automatic legacy-schema migration so startup remains resilient across upgrades.
- US-E5-03: As a user, I want strict config validation (repo identity, schedule format, key paths, healthcheck URL constraints) so invalid settings are blocked before runs.
- US-E5-04: As a user, I want stable JSON encoding/decoding and predictable app paths for config/history/log files so storage is reliable and diff-friendly.
- US-E5-05: As a user, I want run history persisted with retention pruning and newest-first ordering so recent outcomes remain available without unbounded growth.
- US-E5-06: As a user, I want archive inclusion/exclusion composition from user rules, default patterns, directory-content semantics, and marker files so backup scope matches intent.
- US-E5-07: As a user, I want Time Machine exclusions refreshed by macOS version with chunked probing, recovery attempts, normalization, and caching so exclusion data stays accurate and efficient.

## EPIC 6: Security, Secrets & Privileged Execution

- US-E6-01: As a user, I want repository passphrases stored in macOS Keychain and retrieved through a pass-command flow so secrets never live in config files.
- US-E6-02: As a user, I want privileged operations isolated behind a root helper reachable via XPC so elevation boundaries are explicit.
- US-E6-03: As a user, I want the helper restricted to allowlisted commands with argument validation and execution timeouts so privileged scope remains minimal.
- US-E6-04: As a user, I want helper installation to enforce platform and app-location prerequisites and handle approval-required states so install flow is predictable.
- US-E6-05: As a user, I want helper health checks to verify real privileged command execution paths so readiness reflects actual runtime behavior.
- US-E6-06: As a user, I want privileged-runner errors (proxy failure, timeout, no reply) surfaced clearly so helper issues are diagnosable.
- US-E6-07: As a user, I want launch-at-login registration controlled safely with clear success/failure outcomes so startup behavior matches preference.

## EPIC 7: Full Disk Access (FDA) & Permission Recovery

- US-E7-01: As a user, I want FDA assessed conservatively using tmutil and protected-path probes so false-positive permission states are avoided.
- US-E7-02: As a user, I want startup FDA gating before permission-sensitive operations so scans and backups do not fail later in the run.
- US-E7-03: As a user, I want FDA denial states reflected consistently in idle status, diagnostics, and notifications so required action is obvious.
- US-E7-04: As a user, I want in-app FDA prompts with deep links to relevant System Settings panes so remediation is fast.
- US-E7-05: As a user, I want FDA prompt-and-recheck behavior so newly granted permissions can unblock startup without manual restart loops.
- US-E7-06: As a user, I want settings-level FDA diagnostics and re-check actions so permission troubleshooting is available on demand.

## EPIC 8: Observability, Notifications & External Monitoring

- US-E8-01: As a user, I want structured logging to OSLog and local files with runtime log-level control so troubleshooting depth is configurable.
- US-E8-02: As a user, I want live archive progress metrics (bytes, files, rates, throughput, ETA, checkpoint status) so long backups are transparent.
- US-E8-03: As a user, I want completed and failed run metrics parsed and persisted from Borg outputs so historical performance is measurable.
- US-E8-04: As a user, I want notification delivery to respect notification mode (all, errors-only, none) so alert noise matches preference.
- US-E8-05: As a user, I want Healthchecks integration for start/success/fail events with URL validation and non-fatal error handling so external monitoring is useful but never blocks backups.
- US-E8-06: As a user, I want startup and runtime health issues (helper/FDA/scheduling) logged and surfaced with actionable detail so operational problems are easy to triage.

## EPIC 9: Settings & Setup Experience

- US-E9-01: As a user, I want settings organized by Backup Scope, Repository, Security, and Permissions so configuration is easy to navigate.
- US-E9-02: As a user, I want editable exclusion lists (directory contents, glob patterns, marker-based excludes) so backup scope can be tailored without file edits.
- US-E9-03: As a user, I want repository and runtime toggles (sparse mode, launch-at-login, healthchecks, wake scheduling, privileged snapshot mode) so operational policy is centralized.
- US-E9-04: As a user, I want settings to load asynchronously with current config, helper health, passphrase state, launch-at-login state, and FDA diagnostics so controls initialize correctly.
- US-E9-05: As a user, I want Save Changes to persist configuration and report partial failures clearly so I know what applied and what did not.
- US-E9-06: As a user, I want passphrase and helper-install actions to provide clear status, alerts, and follow-up health refresh so sensitive setup tasks are trustworthy.
- US-E9-07: As a user, I want settings to synchronize with orchestrator idle messaging (especially permission states) so app surfaces remain consistent.

## EPIC 10: Architecture, Integration & Developer Tooling

- US-E10-01: As a maintainer, I want the feature code packaged as a standalone module with tests so development and verification are modular.
- US-E10-02: As a maintainer, I want integration ports/adapters across orchestrator, scheduler, startup, preflight, settings, and snapshot services so core logic is decoupled and testable.
- US-E10-03: As a maintainer, I want a shared helper XPC contract and service identity between app and helper targets so interprocess compatibility is stable.
- US-E10-04: As a maintainer, I want operational probe tooling for wake scheduling (IOKit-based script) so wake behavior can be validated outside the app runtime.
- US-E10-05: As a maintainer/admin, I want constrained privilege bootstrap tooling (sudoers setup with validation) so optional elevated workflows can be provisioned safely.
- US-E10-06: As a maintainer, I want bounded directory traversal behavior for exclusion discovery so scans are safe and predictable on large filesystems.
