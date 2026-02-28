import Foundation

public actor WakeSchedulerService {
    private let privilegedRunner: PrivilegedCommandRunner

    public init(privilegedRunner: PrivilegedCommandRunner = PrivilegedCommandRunner()) {
        self.privilegedRunner = privilegedRunner
    }

    public func updateWakeSchedule(dailyTime: String, enabled: Bool) async {
        guard let parsedTime = parseTime(from: dailyTime) else {
            AppLogger.error("Wake scheduling skipped: invalid time \(dailyTime)")
            return
        }

        do {
            let currentSchedule = try await runPMSet(arguments: ["-g", "sched"])
            if hasLegacyDailyWakeRepeat(currentSchedule, hour: parsedTime.hour, minute: parsedTime.minute) {
                _ = try await runPMSet(arguments: ["repeat", "cancel"])
                AppLogger.info("Removed legacy repeating wake schedule")
            }

            guard enabled else {
                AppLogger.info("Wake scheduling disabled")
                return
            }

            guard let next = nextDate(hour: parsedTime.hour, minute: parsedTime.minute) else {
                AppLogger.error("Wake scheduling skipped: could not compute next wake date")
                return
            }

            let dateTime = formatPMSetDate(next)
            _ = try await runPMSet(arguments: ["schedule", "wakeorpoweron", dateTime])
            AppLogger.info("Scheduled one-shot wake at \(dateTime), next wake \(next)")
        } catch {
            AppLogger.error("Failed to schedule auto wake: \(error.localizedDescription)")
        }
    }

    private func parseTime(from hhmm: String) -> (hour: Int, minute: Int)? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return (hour, minute)
    }

    private func nextDate(hour: Int, minute: Int) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
            return nil
        }

        if today > now {
            return today
        }

        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    private func runPMSet(arguments: [String], timeoutSeconds: TimeInterval = 30) async throws -> String {
        let result = try await privilegedRunner.run(
            executable: "/usr/bin/pmset",
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
        let detail = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            throw WakeScheduleError.commandFailed(
                "pmset \(arguments.joined(separator: " ")) failed (exit \(result.exitCode)): \(detail)"
            )
        }
        return detail
    }

    private func hasLegacyDailyWakeRepeat(_ output: String, hour: Int, minute: Int) -> Bool {
        let expectedClock = formatPMSetClock(hour: hour, minute: minute).lowercased()
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).lowercased() }
            .contains { line in
                line.contains("every day")
                && line.contains("wake")
                && line.contains(expectedClock)
            }
    }

    private func formatPMSetClock(hour: Int, minute: Int) -> String {
        let hour12 = ((hour + 11) % 12) + 1
        let suffix = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d%@", hour12, minute, suffix)
    }

    private func formatPMSetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd/yy HH:mm:ss"
        return formatter.string(from: date)
    }
}

private enum WakeScheduleError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return detail
        }
    }
}
