import Foundation

struct BackupScheduleEvaluation: Sendable {
    var shouldTrigger: Bool
    var updatedLastTriggeredDay: String?
}

struct BackupScheduleEvaluator {
    func evaluate(
        dailyTime: String,
        now: Date,
        lastTriggeredDay: String?,
        hasCompletedRunToday: Bool,
        calendar: Calendar = .current
    ) -> BackupScheduleEvaluation {
        let parts = dailyTime.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return BackupScheduleEvaluation(shouldTrigger: false, updatedLastTriggeredDay: lastTriggeredDay)
        }

        let dayKey = "\(calendar.component(.year, from: now))-\(calendar.component(.month, from: now))-\(calendar.component(.day, from: now))"
        if dayKey == lastTriggeredDay {
            return BackupScheduleEvaluation(shouldTrigger: false, updatedLastTriggeredDay: lastTriggeredDay)
        }

        let runTime = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: now
        ) ?? now

        guard now >= runTime else {
            return BackupScheduleEvaluation(shouldTrigger: false, updatedLastTriggeredDay: lastTriggeredDay)
        }

        if hasCompletedRunToday {
            return BackupScheduleEvaluation(shouldTrigger: false, updatedLastTriggeredDay: dayKey)
        }

        return BackupScheduleEvaluation(shouldTrigger: true, updatedLastTriggeredDay: dayKey)
    }
}
