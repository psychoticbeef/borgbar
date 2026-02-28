import Foundation

@MainActor
public final class SleepAssertionService {
    private var activityToken: NSObjectProtocol?

    public init() {}

    public func begin(reason: String) {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )
        AppLogger.info("Sleep assertion enabled: \(reason)")
    }

    public func end() {
        guard let token = activityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        activityToken = nil
        AppLogger.info("Sleep assertion released")
    }
}
