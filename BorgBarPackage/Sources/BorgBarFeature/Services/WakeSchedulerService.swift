import Foundation

public actor WakeSchedulerService {
    private let integration: WakeSchedulerIntegrationPort
    private let planner: WakeSchedulePlanner

    public init(privilegedRunner: PrivilegedCommandRunner = PrivilegedCommandRunner()) {
        self.integration = DefaultWakeSchedulerIntegrationPort(privilegedRunner: privilegedRunner)
        self.planner = WakeSchedulePlanner()
    }

    init(integration: WakeSchedulerIntegrationPort, planner: WakeSchedulePlanner = WakeSchedulePlanner()) {
        self.integration = integration
        self.planner = planner
    }

    public func updateWakeSchedule(dailyTime: String, enabled: Bool) async {
        guard let parsedTime = planner.parseTime(from: dailyTime) else {
            AppLogger.error("Wake scheduling skipped: invalid time \(dailyTime)")
            return
        }

        do {
            let currentSchedule = try await integration.runPMSet(arguments: ["-g", "sched"], timeoutSeconds: 30)
            let outcome = WakeScheduleUpdatePolicy.evaluate(
                hour: parsedTime.hour,
                minute: parsedTime.minute,
                enabled: enabled,
                currentScheduleOutput: currentSchedule,
                planner: planner
            )

            switch outcome {
            case .disabled(let removeLegacyRepeat):
                if removeLegacyRepeat {
                    _ = try await integration.runPMSet(arguments: ["repeat", "cancel"], timeoutSeconds: 30)
                    AppLogger.info("Removed legacy repeating wake schedule")
                }
                AppLogger.info("Wake scheduling disabled")
            case .scheduleUnavailable(let removeLegacyRepeat):
                if removeLegacyRepeat {
                    _ = try await integration.runPMSet(arguments: ["repeat", "cancel"], timeoutSeconds: 30)
                    AppLogger.info("Removed legacy repeating wake schedule")
                }
                AppLogger.error("Wake scheduling skipped: could not compute next wake date")
            case .schedule(let removeLegacyRepeat, let dateTime, let nextWake):
                if removeLegacyRepeat {
                    _ = try await integration.runPMSet(arguments: ["repeat", "cancel"], timeoutSeconds: 30)
                    AppLogger.info("Removed legacy repeating wake schedule")
                }
                _ = try await integration.runPMSet(arguments: ["schedule", "wakeorpoweron", dateTime], timeoutSeconds: 30)
                AppLogger.info("Scheduled one-shot wake at \(dateTime), next wake \(nextWake)")
            }
        } catch {
            AppLogger.error("Failed to schedule auto wake: \(error.localizedDescription)")
        }
    }
}
