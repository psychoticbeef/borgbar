# Review 004 - IOSP (Integration Operation Segregation Principle)

Date: 2026-02-28
Reviewer mode: architecture + clean-code adherence

## Findings (ordered by severity)

### [P1] Dependency-injection regression in startup path
- File: `BorgBarPackage/Sources/BorgBarFeature/BorgBarModel.swift:20`
- `BorgBarModel` receives `configStore` in init and uses it for `BackupScheduler`, but startup now always constructs `StartupCoordinator()` with default integration.
- Effect: scheduler and startup can read/write different config stores in tests or alternate environments; this regresses deterministic DI behavior.
- Recommendation: wire `StartupCoordinator` from the same injected dependencies (or inject a `StartupIntegrationPort` built from that `configStore`).

### [P2] Operation policy moved into integration adapter (IOSP leakage)
- File: `BorgBarPackage/Sources/BorgBarFeature/Services/StartupIntegrationPort.swift:51-67`
- `DefaultStartupIntegrationPort.loadOrCreateConfig()` contains fallback policy (`config = .default` and save) which is operation logic, not pure integration.
- Effect: operation behavior is hidden inside adapter, reducing separability and making policy tests harder.
- Recommendation: move fallback policy to `StartupCoordinator`, keep adapter methods to primitive integration operations (`loadConfig`, `validateConfig`, `saveConfig`).

### [P3] Redundant policy branch/parameter in termination decision
- Files:
  - `BorgBar/AppTerminationPolicy.swift:20-25`
  - `BorgBar/BorgBarApp.swift:120-123`
- `shouldQuitAfterStop(stoppedGracefully:userChoseForceQuit:)` is always called with `stoppedGracefully: false` in current flow.
- Effect: dead branch adds complexity without behavioral value.
- Recommendation: simplify API to `shouldForceQuit(userChoseForceQuit:)` or call with actual `stopped` value in one code path.

## Residual risk
- `BackupOrchestrator` remains an explicit mixed boundary class by design; this is acceptable but should be kept under periodic review for growth and testability.

## Follow-up pass (same day)

Status:
- `[P1]` resolved
- `[P2]` resolved
- `[P3]` resolved

Resolution notes:
- P1 (DI regression): `BorgBarModel` now creates `StartupCoordinator` with `DefaultStartupIntegrationPort(configStore: configStore)`, aligning startup/scheduler config source.
- P2 (policy leakage): `load-or-create` fallback policy moved into `StartupCoordinator`; `StartupIntegrationPort` now exposes primitive integration operations (`loadConfig`, `validateConfig`, `saveConfig`).
- P3 (redundant branch): termination policy API simplified to `shouldQuitAfterForceChoice(userChoseForceQuit:)`; dead `stoppedGracefully` branch removed.

Additional IOSP loop completed:
- `BackupScheduler` now depends on `BackupSchedulerIntegrationPort`.
- Scheduling decision logic extracted to `BackupScheduleEvaluator` (operation-only).
- `BackupOrchestrator` now depends on `BackupOrchestratorIntegrationPort`.
- Orchestrator integration calls (config/keychain/snapshot/borg/history/notify/wake) moved to adapter; orchestrator now holds operation flow/policy.
- `WakeSchedulerService` now depends on `WakeSchedulerIntegrationPort`.
- Wake scheduling decision/planning moved to `WakeSchedulePlanner` (operation-only).

Additional IOSP follow-up loop completed:
- `TimeMachineExclusionService` no longer performs directory traversal integration directly.
- Added `TimeMachineDirectoryCollectorPort` with `DefaultTimeMachineDirectoryCollectorPort` to encapsulate filesystem enumeration and default-pattern pruning at integration boundary.
- `TimeMachineExclusionService` now focuses on refresh policy, traversal-probe caching, chunked tmutil query/recovery strategy, and config update outcomes.

Additional IOSP follow-up loop completed:
- Failure-retry planning extracted to `BackupFailureRetryPlanner` (operation-only, pure scheduling decision).
- Retry timer/task lifecycle extracted to `BackupFailureRetryController` (integration/runtime boundary).
- `BackupOrchestrator` now delegates retry scheduling mechanics instead of owning delay/window task code directly.

Additional IOSP follow-up loop completed:
- Full Disk Access grant-decision policy extracted to `FullDiskAccessDiagnosticsEvaluator` (operation-only).
- `FullDiskAccessService` now focuses on integration probes (tmutil + filesystem) and delegates final grant computation.

Additional IOSP follow-up loop completed:
- Added `BorgBarModelIntegrationPort` for Full Disk Access diagnostics calls.
- `BorgBarModel` now consumes an integration port instead of directly owning `FullDiskAccessService`.

Additional IOSP follow-up loop completed:
- `BackupOrchestrator` no longer constructs `SleepAssertionService` directly.
- Sleep assertion begin/end now runs through `BackupOrchestratorIntegrationPort`, keeping orchestrator execution path operation-only.

Additional IOSP follow-up loop completed:
- Archive progress parsing/state transitions extracted to `ArchiveProgressProcessor`.
- `BackupOrchestrator` now delegates archive progress state mutation and status message synthesis.

Additional IOSP follow-up loop completed:
- Borg `create` argument assembly extracted to `BorgCreateCommandBuilder`.
- `BorgService` now focuses on command execution/error handling and uses the builder for operation policy.

Additional IOSP follow-up loop completed:
- Backup run metrics assembly extracted to `BackupRunMetricsFactory`.
- `BackupOrchestrator` now delegates completed/failed metrics object construction.

Additional IOSP follow-up loop completed:
- `BackupOrchestrator` archive/maintenance path split into dedicated helper operations (`runArchiveAndMaintenance`, `createArchiveWithLockRecovery`, `makeProgressHandler`) to reduce monolithic method scope.

Additional IOSP follow-up loop completed:
- `SettingsView` structurally split into focused UI components in `SettingsComponents.swift` (sidebar, scope/repository/permissions sections, reusable editable/read-only lists).
- `SettingsView` now primarily orchestrates section selection and security actions.

Additional IOSP follow-up loop completed:
- `SettingsViewModel` presentation/status decisions extracted to `SettingsPresentationPolicy` (time machine subtitle, diagnostics lines, idle-status decision).
- View-model now applies pure policy outputs to orchestrator state.

Additional IOSP follow-up loop completed:
- Startup FDA prompt/retry gating extracted from `StartupCoordinator` to `StartupFullDiskAccessGate`.
- Helper status message mapping extracted to `HelperHealthPolicy` and reused from startup/settings UI paths.

Additional IOSP follow-up loop completed:
- Startup config load/create/validate path extracted from `StartupCoordinator` to `StartupConfigBootstrapper`.
- `StartupCoordinator` is now closer to pure startup-flow composition.

Additional IOSP follow-up loop completed:
- Startup Time Machine exclusion refresh path extracted from `StartupCoordinator` to `StartupTimeMachineExclusionRefresher`.
- `StartupCoordinator` now composes startup sub-operations (config bootstrap, FDA gate, TM refresh, helper health).

Additional IOSP follow-up loop completed:
- Security section UI extracted from `SettingsView` to `SecuritySettingsSectionView` in `SettingsComponents.swift`.
- `SettingsView` now acts as higher-level screen composition boundary with fewer embedded section details.

Additional IOSP follow-up loop completed:
- Notification-mode decision logic for startup issues moved out of integration into `NotificationRoutingPolicy`.
- `StartupIntegrationPort` now exposes primitive `notify(title:body:)` and startup operations decide whether to notify.

Additional IOSP follow-up loop completed:
- Remaining inline security action closures in `SettingsView` were moved to dedicated action methods (`handleSavePassphrase`, `handleInstallHelper`) to reduce view-body operational noise.

Additional IOSP follow-up loop completed:
- `BackupScheduler` completion-history interpretation extracted to `BackupHistoryCompletionPolicy`.
- Scheduler now delegates “completed run today” decision to pure operation policy.

Additional IOSP follow-up loop completed:
- Timer lifecycle extracted from `BackupScheduler` into `BackupSchedulerTimerPort`.
- Scheduler now composes timer integration with schedule evaluation operation logic.

Additional IOSP follow-up loop completed:
- Wake schedule update decision path extracted to `WakeScheduleUpdatePolicy` (disabled/schedule/schedule-unavailable with legacy-repeat handling).
- `WakeSchedulerService` now executes integration commands based on policy output.

Additional IOSP follow-up loop completed:
- Remaining permissions recheck inline closure in `SettingsView` moved to `handleRecheckFullDiskAccess` for cleaner screen orchestration.

Additional simplification loop completed (user feedback: reduce over-abstraction):
- Removed low-value wrappers `NotificationRoutingPolicy`, `BackupHistoryCompletionPolicy`, and `BackupSchedulerTimerPort`.
- Inlined small logic back into `StartupCoordinator`, `StartupFullDiskAccessGate`, and `BackupScheduler`.
- Kept higher-value separations (startup sub-operations, wake update policy, settings section components).

Additional simplification loop completed (continued subtractive pass):
- Removed `StartupConfigBootstrapper`, `StartupTimeMachineExclusionRefresher`, and `HelperHealthPolicy` as low-value wrappers.
- Inlined load/create/validate config, TM-refresh flow, and helper-health message mapping back into `StartupCoordinator` / `SettingsComponents`.
