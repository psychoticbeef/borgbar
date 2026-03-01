import Foundation

@MainActor
protocol BackupOrchestratorIntegrationPort: AnyObject {
    func loadConfig() async throws -> AppConfig
    func validateConfig(_ config: AppConfig) async throws
    func passCommand(repoID: String) async -> String
    func runPreflight(
        config: AppConfig,
        onReachabilityRetry: (@Sendable (String) -> Void)?
    ) async throws
    func createSnapshot(dailyTime: String) async throws -> SnapshotRef
    func mountSnapshot(_ snapshot: SnapshotRef) async throws
    func deleteSnapshot(_ snapshot: SnapshotRef, deleteLocalSnapshot: Bool) async
    func createArchive(
        config: AppConfig,
        snapshotMount: String,
        passCommand: String,
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws -> String
    func prune(config: AppConfig, passCommand: String) async throws
    func compact(config: AppConfig, passCommand: String) async throws
    func repositorySizeBytes(config: AppConfig, passCommand: String) async throws -> Int64?
    func suggestTrimToTarget(
        config: AppConfig,
        passCommand: String,
        currentRepositoryBytes: Int64,
        targetRepositoryBytes: Int64
    ) async throws -> RepositoryTrimSuggestion?
    func breakLock(config: AppConfig, passCommand: String, timeoutSeconds: TimeInterval?) async throws
    func terminateActiveProcess()
    func beginSleepAssertion(reason: String)
    func endSleepAssertion()
    func loadHistory() async -> [BackupRunRecord]
    func appendHistory(_ record: BackupRunRecord) async throws
    func notify(title: String, body: String) async
    func updateWakeSchedule(dailyTime: String, enabled: Bool) async
    func pingHealthcheck(config: AppConfig, event: HealthcheckPingEvent) async
}

struct BackupOrchestratorDependencies {
    let configStore: ConfigStore
    let keychain: KeychainService
    let snapshotService: SnapshotService
    let borg: BorgService
    let historyStore: HistoryStore
    let notifications: NotificationService
    let wakeScheduler: WakeSchedulerService
    let sleepAssertion: SleepAssertionService
    let healthchecks: HealthcheckService
}

@MainActor
final class DefaultBackupOrchestratorIntegrationPort: BackupOrchestratorIntegrationPort {
    private let configStore: ConfigStore
    private let keychain: KeychainService
    private let snapshotService: SnapshotService
    private let borg: BorgService
    private let historyStore: HistoryStore
    private let notifications: NotificationService
    private let wakeScheduler: WakeSchedulerService
    private let sleepAssertion: SleepAssertionService
    private let healthchecks: HealthcheckService

    init(dependencies: BackupOrchestratorDependencies) {
        self.configStore = dependencies.configStore
        self.keychain = dependencies.keychain
        self.snapshotService = dependencies.snapshotService
        self.borg = dependencies.borg
        self.historyStore = dependencies.historyStore
        self.notifications = dependencies.notifications
        self.wakeScheduler = dependencies.wakeScheduler
        self.sleepAssertion = dependencies.sleepAssertion
        self.healthchecks = dependencies.healthchecks
    }

    func loadConfig() async throws -> AppConfig {
        try await configStore.load()
    }

    func validateConfig(_ config: AppConfig) async throws {
        try await configStore.validate(config)
    }

    func passCommand(repoID: String) async -> String {
        await keychain.passCommand(repoID: repoID)
    }

    func runPreflight(
        config: AppConfig,
        onReachabilityRetry: (@Sendable (String) -> Void)?
    ) async throws {
        try await PreflightService.run(
            config: config,
            keychain: keychain,
            onReachabilityRetry: onReachabilityRetry
        )
    }

    func createSnapshot(dailyTime: String) async throws -> SnapshotRef {
        try await snapshotService.createSnapshot(dailyTime: dailyTime)
    }

    func mountSnapshot(_ snapshot: SnapshotRef) async throws {
        try await snapshotService.mountSnapshot(snapshot)
    }

    func deleteSnapshot(_ snapshot: SnapshotRef, deleteLocalSnapshot: Bool) async {
        await snapshotService.deleteSnapshot(snapshot, deleteLocalSnapshot: deleteLocalSnapshot)
    }

    func createArchive(
        config: AppConfig,
        snapshotMount: String,
        passCommand: String,
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try await borg.createArchive(
            config: config,
            snapshotMount: snapshotMount,
            passCommand: passCommand,
            onProgressLine: onProgressLine
        )
    }

    func prune(config: AppConfig, passCommand: String) async throws {
        _ = try await borg.prune(config: config, passCommand: passCommand)
    }

    func compact(config: AppConfig, passCommand: String) async throws {
        _ = try await borg.compact(config: config, passCommand: passCommand)
    }

    func repositorySizeBytes(config: AppConfig, passCommand: String) async throws -> Int64? {
        try await borg.repositorySizeBytes(config: config, passCommand: passCommand)
    }

    func suggestTrimToTarget(
        config: AppConfig,
        passCommand: String,
        currentRepositoryBytes: Int64,
        targetRepositoryBytes: Int64
    ) async throws -> RepositoryTrimSuggestion? {
        try await borg.suggestTrimToTarget(
            config: config,
            passCommand: passCommand,
            currentRepositoryBytes: currentRepositoryBytes,
            targetRepositoryBytes: targetRepositoryBytes
        )
    }

    func breakLock(config: AppConfig, passCommand: String, timeoutSeconds: TimeInterval?) async throws {
        try await borg.breakLock(config: config, passCommand: passCommand, timeoutSeconds: timeoutSeconds)
    }

    func terminateActiveProcess() {
        borg.terminateActiveProcess()
    }

    func beginSleepAssertion(reason: String) {
        sleepAssertion.begin(reason: reason)
    }

    func endSleepAssertion() {
        sleepAssertion.end()
    }

    func loadHistory() async -> [BackupRunRecord] {
        (try? await historyStore.load()) ?? []
    }

    func appendHistory(_ record: BackupRunRecord) async throws {
        try await historyStore.append(record)
    }

    func notify(title: String, body: String) async {
        await notifications.notify(title: title, body: body)
    }

    func updateWakeSchedule(dailyTime: String, enabled: Bool) async {
        await wakeScheduler.updateWakeSchedule(dailyTime: dailyTime, enabled: enabled)
    }

    func pingHealthcheck(config: AppConfig, event: HealthcheckPingEvent) async {
        await healthchecks.pingIfConfigured(config: config, event: event)
    }
}
