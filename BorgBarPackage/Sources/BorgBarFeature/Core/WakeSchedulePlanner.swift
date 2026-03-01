import Foundation

struct WakeSchedulePlanner {
    func parseTime(from hhmm: String) -> (hour: Int, minute: Int)? {
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

    func nextWakeDate(hour: Int, minute: Int, referenceDate: Date = Date()) -> Date? {
        let dailyTime = String(format: "%02d:%02d", hour, minute)
        return DailySchedule.nextRunDate(from: dailyTime, referenceDate: referenceDate)
    }

    func hasLegacyDailyWakeRepeat(_ output: String, hour: Int, minute: Int) -> Bool {
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

    func formatPMSetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd/yy HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatPMSetClock(hour: Int, minute: Int) -> String {
        let hour12 = ((hour + 11) % 12) + 1
        let suffix = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d%@", hour12, minute, suffix)
    }
}
