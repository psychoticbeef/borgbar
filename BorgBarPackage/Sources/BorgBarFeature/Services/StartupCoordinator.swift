import Foundation

@MainActor
public final class StartupCoordinator {
    private let configStore: ConfigStore
    private let wakeScheduler: WakeSchedulerService
    private let notifications: NotificationService
    private let helperInstaller: HelperInstallerService
    private let fullDiskAccess: FullDiskAccessService
    private let timeMachineExclusions: TimeMachineExclusionService
    private let promptService: FullDiskAccessPromptService
    private let snapshotService: LocalSnapshotService

    public init(
        configStore: ConfigStore = ConfigStore(),
        wakeScheduler: WakeSchedulerService = WakeSchedulerService(),
        notifications: NotificationService = NotificationService(),
        helperInstaller: HelperInstallerService = HelperInstallerService(),
        fullDiskAccess: FullDiskAccessService = FullDiskAccessService(),
        timeMachineExclusions: TimeMachineExclusionService = TimeMachineExclusionService(),
        promptService: FullDiskAccessPromptService = FullDiskAccessPromptService(),
        snapshotService: LocalSnapshotService = LocalSnapshotService()
    ) {
        self.configStore = configStore
        self.wakeScheduler = wakeScheduler
        self.notifications = notifications
        self.helperInstaller = helperInstaller
        self.fullDiskAccess = fullDiskAccess
        self.timeMachineExclusions = timeMachineExclusions
        self.promptService = promptService
        self.snapshotService = snapshotService
    }

    public func runStartup(orchestrator: BackupOrchestrator, fullDiskAccessRequiredMessage: String) async {
        await orchestrator.loadHistory()
        await snapshotService.cleanupStaleSnapshots()
        guard let loadedConfig = await loadOrCreateConfig() else { return }

        let hasFullDiskAccess = await ensureFullDiskAccess(
            config: loadedConfig,
            orchestrator: orchestrator,
            fullDiskAccessRequiredMessage: fullDiskAccessRequiredMessage
        )

        let config: AppConfig
        if hasFullDiskAccess {
            config = await refreshTimeMachineExclusionsIfNeeded(
                config: loadedConfig,
                orchestrator: orchestrator,
                fullDiskAccessRequiredMessage: fullDiskAccessRequiredMessage
            )
        } else {
            AppLogger.info("Skipping Time Machine exclusion refresh until Full Disk Access is granted")
            config = loadedConfig
        }

        await wakeScheduler.updateWakeSchedule(
            dailyTime: config.schedule.dailyTime,
            enabled: config.schedule.wakeEnabled
        )
        await checkHelperHealth(config: config, orchestrator: orchestrator)
    }

    private func loadOrCreateConfig() async -> AppConfig? {
        var config: AppConfig
        do {
            config = try await configStore.load()
            try await configStore.validate(config)
        } catch {
            do {
                config = .default
                try await configStore.save(config)
                AppLogger.info("Wrote default app-config.json")
            } catch {
                AppLogger.error("Failed to write default config: \(error.localizedDescription)")
                return nil
            }
        }

        return config
    }

    private func refreshTimeMachineExclusionsIfNeeded(
        config: AppConfig,
        orchestrator: BackupOrchestrator,
        fullDiskAccessRequiredMessage: String
    ) async -> AppConfig {
        guard await fullDiskAccess.hasFullDiskAccess() else {
            orchestrator.setIdleStatus(fullDiskAccessRequiredMessage)
            AppLogger.info("Skipping Time Machine exclusion refresh until Full Disk Access is granted")
            return config
        }

        orchestrator.setIdleStatus("Refreshing Time Machine exclusions...")
        do {
            let result = try await timeMachineExclusions.refreshIfNeeded(config: config)
            guard result.didUpdate else {
                orchestrator.setIdleStatus("Idle")
                return config
            }

            try await configStore.save(result.config)
            let osVersion = result.config.repo.timeMachineExclusionOSVersion ?? "unknown"
            let count = result.config.repo.timeMachineExcludedPaths.count
            AppLogger.info("Refreshed Time Machine exclusions for macOS \(osVersion): \(count) paths")
            orchestrator.setIdleStatus("Time Machine exclusions refreshed (\(count) paths)")
            return result.config
        } catch {
            let message = "Time Machine exclusions scan failed. Open Logs for details."
            AppLogger.error("Failed to refresh Time Machine exclusions: \(error.localizedDescription)")
            orchestrator.setIdleStatus(message)
            return config
        }
    }

    private func checkHelperHealth(config: AppConfig, orchestrator: BackupOrchestrator) async {
        let health = await helperInstaller.healthStatus()
        let message: String
        switch health {
        case .healthy:
            return
        case .notInstalled:
            message = "Privileged helper is not installed. Open Settings and click Install Helper."
        case .unhealthy(let detail):
            message = detail
        }

        orchestrator.setIdleStatus(message)
        AppLogger.error(message)
        await notifyHelperIssueIfNeeded(mode: config.preferences.notifications, body: message)
    }

    private func ensureFullDiskAccess(
        config: AppConfig,
        orchestrator: BackupOrchestrator,
        fullDiskAccessRequiredMessage: String
    ) async -> Bool {
        let firstCheck = await fullDiskAccess.diagnostics()
        if firstCheck.granted {
            return true
        }
        // TCC updates can lag briefly after the user toggles access.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let secondCheck = await fullDiskAccess.diagnostics()
        guard !secondCheck.granted else { return true }

        orchestrator.setIdleStatus(fullDiskAccessRequiredMessage)
        AppLogger.error(fullDiskAccessRequiredMessage)
        if let probeLine = failedProbeLine(from: secondCheck) {
            AppLogger.error(probeLine)
        }
        await notifyFullDiskAccessIssueIfNeeded(mode: config.preferences.notifications, body: fullDiskAccessRequiredMessage)
        await promptService.promptIfNeeded {
            self.fullDiskAccess.openSystemSettings()
        }

        // If the user grants access from the prompt path right away, continue startup.
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await fullDiskAccess.hasFullDiskAccess() {
                orchestrator.setIdleStatus("Full Disk Access granted")
                AppLogger.info("Full Disk Access granted after prompt")
                return true
            }
        }
        return false
    }

    private func failedProbeLine(from diagnostics: FullDiskAccessDiagnostics) -> String? {
        if let denied = diagnostics.probes.first(where: { $0.state == .permissionDenied }) {
            let detail = denied.detail ?? "permission denied"
            return "Full Disk Access probe blocked at \(denied.path): \(detail)"
        }
        if let errored = diagnostics.probes.first(where: { $0.state == .otherError }) {
            let detail = errored.detail ?? "unknown error"
            return "Full Disk Access probe error at \(errored.path): \(detail)"
        }
        return nil
    }

    private func notifyHelperIssueIfNeeded(mode: NotificationMode, body: String) async {
        guard mode != .none else { return }
        await notifications.notify(title: "BorgBar Helper Attention Needed", body: body)
    }

    private func notifyFullDiskAccessIssueIfNeeded(mode: NotificationMode, body: String) async {
        guard mode != .none else { return }
        await notifications.notify(title: "BorgBar Full Disk Access Needed", body: body)
    }
}
