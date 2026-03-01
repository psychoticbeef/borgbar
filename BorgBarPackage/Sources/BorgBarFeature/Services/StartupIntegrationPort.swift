import Foundation

@MainActor
protocol StartupIntegrationPort: AnyObject {
    func cleanupStaleSnapshots() async
    func loadConfig() async throws -> AppConfig
    func validateConfig(_ config: AppConfig) async throws
    func saveConfig(_ config: AppConfig) async throws
    func refreshTimeMachineExclusions(config: AppConfig) async throws -> (config: AppConfig, didUpdate: Bool)
    func hasFullDiskAccess() async -> Bool
    func fullDiskAccessDiagnostics() async -> FullDiskAccessDiagnostics
    func promptForFullDiskAccessIfNeeded() async
    func helperHealthStatus() async -> HelperHealthStatus
    func updateWakeSchedule(for config: AppConfig) async
    func syncLaunchAtLogin(for config: AppConfig) async throws
    func notify(title: String, body: String) async
}

@MainActor
final class DefaultStartupIntegrationPort: StartupIntegrationPort {
    private let configStore: ConfigStore
    private let wakeScheduler: WakeSchedulerService
    private let notifications: NotificationService
    private let helperInstaller: HelperInstallerService
    private let fullDiskAccess: FullDiskAccessService
    private let timeMachineExclusions: TimeMachineExclusionService
    private let promptService: FullDiskAccessPromptService
    private let snapshotService: LocalSnapshotService
    private let launchAtLogin: LaunchAtLoginService

    init(
        configStore: ConfigStore = ConfigStore(),
        wakeScheduler: WakeSchedulerService = WakeSchedulerService(),
        notifications: NotificationService = NotificationService(),
        helperInstaller: HelperInstallerService = HelperInstallerService(),
        fullDiskAccess: FullDiskAccessService = FullDiskAccessService(),
        timeMachineExclusions: TimeMachineExclusionService = TimeMachineExclusionService(),
        promptService: FullDiskAccessPromptService = FullDiskAccessPromptService(),
        snapshotService: LocalSnapshotService = LocalSnapshotService(),
        launchAtLogin: LaunchAtLoginService = LaunchAtLoginService()
    ) {
        self.configStore = configStore
        self.wakeScheduler = wakeScheduler
        self.notifications = notifications
        self.helperInstaller = helperInstaller
        self.fullDiskAccess = fullDiskAccess
        self.timeMachineExclusions = timeMachineExclusions
        self.promptService = promptService
        self.snapshotService = snapshotService
        self.launchAtLogin = launchAtLogin
    }

    func cleanupStaleSnapshots() async {
        await snapshotService.cleanupStaleSnapshots()
    }

    func loadConfig() async throws -> AppConfig {
        try await configStore.load()
    }

    func validateConfig(_ config: AppConfig) async throws {
        try await configStore.validate(config)
    }

    func saveConfig(_ config: AppConfig) async throws {
        try await configStore.save(config)
    }

    func refreshTimeMachineExclusions(config: AppConfig) async throws -> (config: AppConfig, didUpdate: Bool) {
        let result = try await timeMachineExclusions.refreshIfNeeded(config: config)
        if result.didUpdate {
            try await configStore.save(result.config)
        }
        return result
    }

    func hasFullDiskAccess() async -> Bool {
        await fullDiskAccess.hasFullDiskAccess()
    }

    func fullDiskAccessDiagnostics() async -> FullDiskAccessDiagnostics {
        await fullDiskAccess.diagnostics()
    }

    func promptForFullDiskAccessIfNeeded() async {
        await promptService.promptIfNeeded {
            self.fullDiskAccess.openSystemSettings()
        }
    }

    func helperHealthStatus() async -> HelperHealthStatus {
        await helperInstaller.healthStatus()
    }

    func updateWakeSchedule(for config: AppConfig) async {
        await wakeScheduler.updateWakeSchedule(
            dailyTime: config.schedule.dailyTime,
            enabled: config.schedule.wakeEnabled
        )
    }

    func syncLaunchAtLogin(for config: AppConfig) async throws {
        try await launchAtLogin.setEnabled(config.preferences.launchAtLogin)
    }

    func notify(title: String, body: String) async {
        await notifications.notify(title: title, body: body)
    }
}
