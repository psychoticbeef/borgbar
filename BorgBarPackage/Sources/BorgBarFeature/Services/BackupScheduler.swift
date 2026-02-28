import Foundation

@MainActor
public final class BackupScheduler: ObservableObject {
    private var timer: Timer?
    private let orchestrator: BackupOrchestrator
    private let configStore: ConfigStore
    private let historyStore: HistoryStore
    private var lastTriggeredDay: String?

    public init(
        orchestrator: BackupOrchestrator,
        configStore: ConfigStore = ConfigStore(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.orchestrator = orchestrator
        self.configStore = configStore
        self.historyStore = historyStore
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
        guard !orchestrator.isRunning else { return }
        guard let config = try? await configStore.load() else { return }

        let parts = config.schedule.dailyTime.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return }

        let now = Date()
        let calendar = Calendar.current
        let dayKey = "\(calendar.component(.year, from: now))-\(calendar.component(.month, from: now))-\(calendar.component(.day, from: now))"
        if dayKey == lastTriggeredDay { return }

        let runTime = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: now
        ) ?? now

        if now >= runTime {
            if await hasCompletedRunToday(referenceDate: now) {
                lastTriggeredDay = dayKey
                return
            }
            lastTriggeredDay = dayKey
            orchestrator.startScheduledRun()
        }
    }

    private func hasCompletedRunToday(referenceDate: Date) async -> Bool {
        guard let records = try? await historyStore.load() else { return false }
        let calendar = Calendar.current
        return records.contains { record in
            guard calendar.isDate(record.startedAt, inSameDayAs: referenceDate) else {
                return false
            }
            if record.outcome == .success || record.outcome == .successWithWarning {
                return true
            }
            // Backward-compat: older runs could be marked failed despite a completed archive summary.
            if record.summary.contains("Archive fingerprint:"),
               record.summary.contains("Time (end):") {
                return true
            }
            return false
        }
    }
}
