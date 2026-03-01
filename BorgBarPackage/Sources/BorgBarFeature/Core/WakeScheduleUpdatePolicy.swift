import Foundation

enum WakeScheduleUpdatePolicyOutcome {
    case disabled(removeLegacyRepeat: Bool)
    case schedule(removeLegacyRepeat: Bool, dateTime: String, nextWake: Date)
    case scheduleUnavailable(removeLegacyRepeat: Bool)
}

enum WakeScheduleUpdatePolicy {
    static func evaluate(
        hour: Int,
        minute: Int,
        enabled: Bool,
        currentScheduleOutput: String,
        planner: WakeSchedulePlanner,
        referenceDate: Date = Date()
    ) -> WakeScheduleUpdatePolicyOutcome {
        let hasLegacyRepeat = planner.hasLegacyDailyWakeRepeat(
            currentScheduleOutput,
            hour: hour,
            minute: minute
        )

        guard enabled else {
            return .disabled(removeLegacyRepeat: hasLegacyRepeat)
        }

        guard let next = planner.nextWakeDate(hour: hour, minute: minute, referenceDate: referenceDate) else {
            return .scheduleUnavailable(removeLegacyRepeat: hasLegacyRepeat)
        }

        return .schedule(
            removeLegacyRepeat: hasLegacyRepeat,
            dateTime: planner.formatPMSetDate(next),
            nextWake: next
        )
    }
}
