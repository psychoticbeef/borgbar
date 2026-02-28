# IOSP Class Review (Looped)

Date: 2026-02-28  
Scope: `BorgBar` app target + `BorgBarFeature` package

## IOSP rubric used
- `I` (Input): receives external events/commands/UI actions.
- `O` (Output): writes side effects to OS, network, filesystem, keychain, notifications.
- `S` (State): owns mutable app/runtime state.
- `P` (Process): business orchestration / multi-step policy flow.

Rule applied:
- Normal types should stay focused (ideally one primary IOSP concern, max two).
- Mixed IOSP is allowed only in explicit boundary/orchestrator classes.

## Loop 1 findings
- `BorgBarModel` mixed `I/O/S/P` (startup policy + FDA prompt + helper/TM checks + UI state gateway).
- Startup readiness logic was scattered in `BorgBarModel` instead of a dedicated process boundary.

## Refactor executed
- Added [`StartupCoordinator`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/StartupCoordinator.swift) to own startup process flow (`P`) and related side effects (`O`).
- Added [`FullDiskAccessPromptService`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/Services/FullDiskAccessPromptService.swift) to isolate FDA prompt UI output (`O`) from model state/process.
- Reduced [`BorgBarModel`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/BorgBarModel.swift) to state gateway + startup kickoff.
- Added [`SettingsViewModel`](/Users/da/code/BorgBar/BorgBarPackage/Sources/BorgBarFeature/UI/SettingsViewModel.swift) to move settings-side process/output work out of `SettingsView`.

## Loop 2 class-by-class status

| Type | File | IOSP Role | Status |
|---|---|---|---|
| `AppDelegate` | `BorgBar/BorgBarApp.swift` | `I+O+S+P` | Boundary class (allowed) |
| `BorgBarModel` | `BorgBarFeature/BorgBarModel.swift` | `S+P` | Improved, acceptable |
| `BackupOrchestrator` | `Orchestrator/BackupOrchestrator.swift` | `P+S+O` | Boundary class (allowed) |
| `BackupScheduler` | `Services/BackupScheduler.swift` | `P+S` | Focused, acceptable |
| `StartupCoordinator` | `Services/StartupCoordinator.swift` | `P+O` | Boundary class (allowed) |
| `SettingsView` | `UI/SettingsView.swift` | `I+S` | Improved, acceptable |
| `SettingsViewModel` | `UI/SettingsViewModel.swift` | `P+O+S` | Boundary class (allowed) |
| `MenuBarView` | `UI/MenuBarView.swift` | `I+O` | UI boundary, acceptable |
| `ContentView` | `ContentView.swift` | `I` | Focused |
| `CommandRunner` | `Services/CommandRunner.swift` | `O` | Focused |
| `PrivilegedCommandRunner` | `Services/PrivilegedCommandRunner.swift` | `O` | Focused |
| `HelperInstallerService` | `Services/HelperInstallerService.swift` | `O` | Focused |
| `FullDiskAccessService` | `Services/FullDiskAccessService.swift` | `O` | Focused |
| `FullDiskAccessPromptService` | `Services/FullDiskAccessPromptService.swift` | `O` | Focused |
| `LocalSnapshotService` | `Services/SnapshotService.swift` | `P+O` | Focused service boundary |
| `TimeMachineExclusionService` | `Services/TimeMachineExclusionService.swift` | `P+O` | Focused service boundary |
| `BorgService` | `Services/BorgService.swift` | `O` | Focused |
| `WakeSchedulerService` | `Services/WakeSchedulerService.swift` | `P+O` | Focused service boundary |
| `PreflightService` | `Services/PreflightService.swift` | `P+O` | Focused service boundary |
| `ConfigStore` | `Services/ConfigStore.swift` | `O` | Focused |
| `HistoryStore` | `Services/HistoryStore.swift` | `O` | Focused |
| `KeychainService` | `Services/KeychainService.swift` | `O` | Focused |
| `NotificationService` | `Services/NotificationService.swift` | `O` | Focused |
| `SleepAssertionService` | `Services/SleepAssertionService.swift` | `O` | Focused |
| `AppLogger` | `Services/AppLogger.swift` | `O` | Focused |
| `AppPaths` | `Services/AppPaths.swift` | `S` | Focused |

## Concentrated IOSP-mixed boundaries
After refactor, intentional mixed-concern boundaries are concentrated to:
- `AppDelegate`
- `BackupOrchestrator`
- `StartupCoordinator`
- `SettingsViewModel`

All other classes/services are single-purpose or near-single-purpose by IOSP rubric.
