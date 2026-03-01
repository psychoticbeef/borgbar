import Foundation

struct BackupFailureRetryPlan: Sendable {
    let retryAt: Date
    let cutoffAt: Date
}

enum BackupFailureRetryPlanningResult: Sendable {
    case scheduled(BackupFailureRetryPlan)
    case invalidSchedule
    case outsideWindow(nextScheduledRun: Date)
}

enum BackupFailureRetryPlanner {
    static let defaultRetryDelay: TimeInterval = 60 * 60

    static func plan(
        now: Date,
        dailyTime: String,
        retryDelay: TimeInterval = defaultRetryDelay
    ) -> BackupFailureRetryPlanningResult {
        guard let nextScheduledRun = DailySchedule.nextRunDate(from: dailyTime, referenceDate: now) else {
            return .invalidSchedule
        }

        let retryAt = now.addingTimeInterval(retryDelay)
        guard retryAt < nextScheduledRun else {
            return .outsideWindow(nextScheduledRun: nextScheduledRun)
        }

        return .scheduled(BackupFailureRetryPlan(retryAt: retryAt, cutoffAt: nextScheduledRun))
    }
}
