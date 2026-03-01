# IOSP Class Review (Looped)

Date: 2026-02-28  
Scope: `BorgBar` app target + `BorgBarFeature` package

## IOSP rubric used
- `Integration`: code that talks to external systems (UI/AppKit, OS commands, filesystem, keychain, network, notifications).
- `Operation`: code that implements business operations/policy and coordinates domain workflow.

Rule applied:
- Keep operation logic separated from integration details.
- Mixed integration+operation is allowed only in explicit boundary/orchestrator classes.

## Loop 1 findings
- `BorgBarModel` mixed integration+operation responsibilities (startup policy + FDA prompt + helper/TM checks + UI state gateway).
- Startup readiness logic was scattered in `BorgBarModel` instead of a dedicated process boundary.

## Refactor executed
- Added [`StartupCoordinator`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/StartupCoordinator.swift) to own startup operation flow and explicitly contain boundary integration.
- Added [`FullDiskAccessPromptService`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/FullDiskAccessPromptService.swift) to isolate FDA prompt integration from model operation/state logic.
- Reduced [`BorgBarModel`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/BorgBarModel.swift) to state gateway + startup kickoff.
- Added [`SettingsViewModel`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/UI/SettingsViewModel.swift) to move settings-side process/output work out of `SettingsView`.
- Added explicit integration ports:
  - [`StartupIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/StartupIntegrationPort.swift)
  - [`SettingsIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/UI/SettingsIntegrationPort.swift)
  - [`BorgBarModelIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/BorgBarModelIntegrationPort.swift)
- Added scheduler segregation:
  - [`BackupSchedulerIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/BackupSchedulerIntegrationPort.swift)
  - [`BackupScheduleEvaluator`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/BackupScheduleEvaluator.swift)
  - [`BackupRunMetricsFactory`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/BackupRunMetricsFactory.swift)
- Added settings presentation policy segregation:
  - [`SettingsPresentationPolicy`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/SettingsPresentationPolicy.swift)
- Added backup failure-retry segregation:
  - [`BackupFailureRetryPlanner`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/BackupFailureRetryPlanner.swift)
  - [`BackupFailureRetryController`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/BackupFailureRetryController.swift)
- Added orchestrator segregation:
  - [`BackupOrchestratorIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/BackupOrchestratorIntegrationPort.swift)
  - `BackupOrchestrator` sleep assertion lifecycle now routed through the integration port (no direct integration service construction in orchestrator flow)
  - [`ArchiveProgressProcessor`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/ArchiveProgressProcessor.swift) now owns archive progress state transitions and status synthesis
  - `BackupOrchestrator` archive/maintenance path further decomposed into helper operations (`runArchiveAndMaintenance`, `createArchiveWithLockRecovery`, `makeProgressHandler`)
- Added wake scheduling segregation:
  - [`WakeSchedulerIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/WakeSchedulerIntegrationPort.swift)
  - [`WakeSchedulePlanner`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/WakeSchedulePlanner.swift)
  - [`WakeScheduleUpdatePolicy`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/WakeScheduleUpdatePolicy.swift)
- Added preflight segregation:
  - [`PreflightIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/PreflightIntegrationPort.swift)
- Added snapshot lifecycle segregation:
  - [`LocalSnapshotIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/LocalSnapshotIntegrationPort.swift)
- Added Time Machine command segregation:
  - [`TimeMachineExclusionIntegrationPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/TimeMachineExclusionIntegrationPort.swift)
- Added Time Machine directory traversal segregation:
  - [`TimeMachineDirectoryCollectorPort`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/TimeMachineDirectoryCollectorPort.swift)
- Added Full Disk Access diagnostics segregation:
  - [`FullDiskAccessDiagnosticsEvaluator`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/FullDiskAccessDiagnosticsEvaluator.swift)
- Added borg create-arguments segregation:
  - [`BorgCreateCommandBuilder`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Core/BorgCreateCommandBuilder.swift)
- Added settings structural component split:
  - [`SettingsComponents.swift`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/UI/SettingsComponents.swift) now contains sidebar/section/list view components
  - [`SettingsView.swift`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/UI/SettingsView.swift) reduced to screen orchestration + security action boundary
- Added startup full disk access gate segregation:
  - [`StartupFullDiskAccessGate`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/StartupFullDiskAccessGate.swift) now owns startup FDA prompt/retry gating flow
- Subtractive simplification pass:
  - removed `BackupSchedulerTimerPort`, `BackupHistoryCompletionPolicy`, `NotificationRoutingPolicy`, `StartupConfigBootstrapper`, `StartupTimeMachineExclusionRefresher`, and `HelperHealthPolicy` as low-value wrappers
  - inlined their small logic into `BackupScheduler`, `StartupCoordinator`, and `StartupFullDiskAccessGate`
- Updated operation classes (`StartupCoordinator`, `SettingsViewModel`) to depend on ports instead of concrete integration services.
- Added [`AppTerminationPolicy`](/Users/da/code/BorgBar/BorgBar/AppTerminationPolicy.swift) and moved termination decision rules out of `AppDelegate`.

## Loop 3 class-by-class status

| Type | File | IOSP Role | Status |
|---|---|---|---|
| `AppDelegate` | `BorgBar/BorgBarApp.swift` | `Integration` | Improved, acceptable |
| `AppTerminationPolicy` | `BorgBar/AppTerminationPolicy.swift` | `Operation` | Focused |
| `BorgBarModel` | `BorgBarFeature/BorgBarModel.swift` | `Operation` | Improved, acceptable |
| `BorgBarModelIntegrationPort` + `DefaultBorgBarModelIntegrationPort` | `Services/BorgBarModelIntegrationPort.swift` | `Integration` | Focused adapter |
| `BackupOrchestrator` | `Orchestrator/BackupOrchestrator.swift` | `Operation` | Improved, acceptable |
| `ArchiveProgressProcessor` | `Core/ArchiveProgressProcessor.swift` | `Operation` | Focused |
| `BackupOrchestratorIntegrationPort` + `DefaultBackupOrchestratorIntegrationPort` | `Services/BackupOrchestratorIntegrationPort.swift` | `Integration` | Focused adapter |
| `BackupScheduler` | `Services/BackupScheduler.swift` | `Operation` | Improved, acceptable |
| `BackupSchedulerIntegrationPort` + `DefaultBackupSchedulerIntegrationPort` | `Services/BackupSchedulerIntegrationPort.swift` | `Integration` | Focused adapter |
| `BackupScheduleEvaluator` | `Core/BackupScheduleEvaluator.swift` | `Operation` | Focused |
| `BackupRunMetricsFactory` | `Core/BackupRunMetricsFactory.swift` | `Operation` | Focused |
| `SettingsPresentationPolicy` | `Core/SettingsPresentationPolicy.swift` | `Operation` | Focused |
| `BackupFailureRetryPlanner` | `Core/BackupFailureRetryPlanner.swift` | `Operation` | Focused |
| `BackupFailureRetryController` | `Services/BackupFailureRetryController.swift` | `Integration` | Focused boundary |
| `StartupCoordinator` | `Services/StartupCoordinator.swift` | `Operation` | Improved, acceptable |
| `StartupFullDiskAccessGate` | `Services/StartupFullDiskAccessGate.swift` | `Operation` | Focused |
| `StartupIntegrationPort` + `DefaultStartupIntegrationPort` | `Services/StartupIntegrationPort.swift` | `Integration` | Focused adapter |
| `SettingsView` | `UI/SettingsView.swift` | `Integration` | Improved, acceptable |
| `SettingsComponents` | `UI/SettingsComponents.swift` | `Integration` | Focused UI components |
| `SettingsViewModel` | `UI/SettingsViewModel.swift` | `Operation` | Improved, acceptable |
| `SettingsIntegrationPort` + `DefaultSettingsIntegrationPort` | `UI/SettingsIntegrationPort.swift` | `Integration` | Focused adapter |
| `MenuBarView` | `UI/MenuBarView.swift` | `Integration` | UI boundary, acceptable |
| `ContentView` | `ContentView.swift` | `Integration` | Focused |
| `CommandRunner` | `Services/CommandRunner.swift` | `Integration` | Focused |
| `PrivilegedCommandRunner` | `Services/PrivilegedCommandRunner.swift` | `Integration` | Focused |
| `HelperInstallerService` | `Services/HelperInstallerService.swift` | `Integration` | Focused |
| `FullDiskAccessService` | `Services/FullDiskAccessService.swift` | `Integration` | Focused |
| `FullDiskAccessDiagnosticsEvaluator` | `Core/FullDiskAccessDiagnosticsEvaluator.swift` | `Operation` | Focused |
| `FullDiskAccessPromptService` | `Services/FullDiskAccessPromptService.swift` | `Integration` | Focused |
| `LocalSnapshotService` | `Services/SnapshotService.swift` | `Operation` | Improved, acceptable |
| `LocalSnapshotIntegrationPort` + `DefaultLocalSnapshotIntegrationPort` | `Services/LocalSnapshotIntegrationPort.swift` | `Integration` | Focused adapter |
| `TimeMachineExclusionService` | `Services/TimeMachineExclusionService.swift` | `Operation` | Improved, acceptable |
| `TimeMachineExclusionIntegrationPort` + `TMExclusionIntegrationAdapter` | `Services/TimeMachineExclusionIntegrationPort.swift` | `Integration` | Focused adapter |
| `TimeMachineDirectoryCollectorPort` + `DefaultTimeMachineDirectoryCollectorPort` | `Services/TimeMachineDirectoryCollectorPort.swift` | `Integration` | Focused adapter |
| `BorgService` | `Services/BorgService.swift` | `Integration` | Improved, acceptable |
| `BorgCreateCommandBuilder` | `Core/BorgCreateCommandBuilder.swift` | `Operation` | Focused |
| `WakeSchedulerService` | `Services/WakeSchedulerService.swift` | `Operation` | Improved, acceptable |
| `WakeSchedulerIntegrationPort` + `DefaultWakeSchedulerIntegrationPort` | `Services/WakeSchedulerIntegrationPort.swift` | `Integration` | Focused adapter |
| `WakeSchedulePlanner` | `Core/WakeSchedulePlanner.swift` | `Operation` | Focused |
| `WakeScheduleUpdatePolicy` | `Core/WakeScheduleUpdatePolicy.swift` | `Operation` | Focused |
| `PreflightService` | `Services/PreflightService.swift` | `Operation` | Improved, acceptable |
| `PreflightIntegrationPort` + `DefaultPreflightIntegrationPort` | `Services/PreflightIntegrationPort.swift` | `Integration` | Focused adapter |
| `ConfigStore` | `Services/ConfigStore.swift` | `Integration` | Focused |
| `HistoryStore` | `Services/HistoryStore.swift` | `Integration` | Focused |
| `KeychainService` | `Services/KeychainService.swift` | `Integration` | Focused |
| `NotificationService` | `Services/NotificationService.swift` | `Integration` | Focused |
| `SleepAssertionService` | `Services/SleepAssertionService.swift` | `Integration` | Focused |
| `AppLogger` | `Services/AppLogger.swift` | `Integration` | Focused |
| `AppPaths` | `Services/AppPaths.swift` | `Operation` | Focused |

## Concentrated IOSP-mixed boundaries
After refactor, no additional mixed-concern service boundary remains outside explicit workflow orchestrators.

Classes/services are now single-purpose or near-single-purpose by IOSP rubric, with operation classes depending on integration ports.
