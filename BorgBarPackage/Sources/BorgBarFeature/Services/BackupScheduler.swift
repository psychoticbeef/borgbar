import Foundation

@MainActor
public final class BackupScheduler: ObservableObject {
    private var timer: Timer?
    private let integration: BackupSchedulerIntegrationPort
    private let evaluator: BackupScheduleEvaluator
    private var lastTriggeredDay: String?

    public init(
        orchestrator: BackupOrchestrator,
        configStore: ConfigStore = ConfigStore(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.integration = DefaultBackupSchedulerIntegrationPort(
            orchestrator: orchestrator,
            configStore: configStore,
            historyStore: historyStore
        )
        self.evaluator = BackupScheduleEvaluator()
    }

    init(
        integration: BackupSchedulerIntegrationPort,
        evaluator: BackupScheduleEvaluator = BackupScheduleEvaluator()
    ) {
        self.integration = integration
        self.evaluator = evaluator
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
        timer?.tolerance = 5
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        guard !integration.isBackupRunning() else { return }
        guard let dailyTime = await integration.loadScheduleDailyTime() else { return }

        let now = Date()
        let records = await integration.loadHistory()
        let completedToday = hasCompletedRunToday(records: records, referenceDate: now)
        let decision = evaluator.evaluate(
            dailyTime: dailyTime,
            now: now,
            lastTriggeredDay: lastTriggeredDay,
            hasCompletedRunToday: completedToday
        )
        if let dayKey = decision.updatedLastTriggeredDay {
            lastTriggeredDay = dayKey
        }
        if decision.shouldTrigger {
            integration.startScheduledRun()
        }
    }

    private func hasCompletedRunToday(records: [BackupRunRecord], referenceDate: Date) -> Bool {
        let calendar = Calendar.current
        return records.contains { record in
            guard calendar.isDate(record.startedAt, inSameDayAs: referenceDate) else {
                return false
            }
            if record.outcome == .success || record.outcome == .successWithWarning {
                return true
            }
            // Backward-compat: older runs could be marked failed despite a completed archive summary.
            return record.summary.contains("Archive fingerprint:")
                && record.summary.contains("Time (end):")
        }
    }
}
