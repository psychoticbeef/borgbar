import Foundation

@MainActor
protocol BackupSchedulerIntegrationPort: AnyObject {
    func isBackupRunning() -> Bool
    func loadScheduleDailyTime() async -> String?
    func loadHistory() async -> [BackupRunRecord]
    func startScheduledRun()
}

@MainActor
final class DefaultBackupSchedulerIntegrationPort: BackupSchedulerIntegrationPort {
    private let orchestrator: BackupOrchestrator
    private let configStore: ConfigStore
    private let historyStore: HistoryStore

    init(
        orchestrator: BackupOrchestrator,
        configStore: ConfigStore = ConfigStore(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.orchestrator = orchestrator
        self.configStore = configStore
        self.historyStore = historyStore
    }

    func isBackupRunning() -> Bool {
        orchestrator.isRunning
    }

    func loadScheduleDailyTime() async -> String? {
        let config = try? await configStore.load()
        return config?.schedule.dailyTime
    }

    func loadHistory() async -> [BackupRunRecord] {
        (try? await historyStore.load()) ?? []
    }

    func startScheduledRun() {
        orchestrator.startScheduledRun()
    }
}
