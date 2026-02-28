import Foundation

enum SnapshotDateParser {
    private static let snapshotPattern = #"\d{4}-\d{2}-\d{2}-\d{6}"#

    static func parseSnapshotDate(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return extractSnapshotDates(from: trimmed).last
    }

    static func extractSnapshotDates(from output: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: snapshotPattern) else {
            return []
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, range: range)
        var dates: [String] = []
        dates.reserveCapacity(matches.count)
        for match in matches {
            guard let matchedRange = Range(match.range, in: output) else { continue }
            dates.append(String(output[matchedRange]))
        }
        return dates
    }

    static func isSameDay(snapshotDate: String, referenceDate: Date, timeZone: TimeZone = .current) -> Bool {
        let dayPrefix = snapshotDate
            .split(separator: "-")
            .prefix(3)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dayPrefix.isEmpty else { return false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return dayPrefix == formatter.string(from: referenceDate)
    }
}

enum SnapshotMountFailureAnalyzer {
    static func shouldRetry(failures: [String]) -> Bool {
        let joined = failures.joined(separator: " ").lowercased()
        return joined.contains("resource busy") || joined.contains("no such file or directory")
    }

    static func classify(failures: [String]) -> String {
        let joined = failures.joined(separator: " | ")
        let lower = joined.lowercased()

        if lower.contains("operation not permitted") {
            return "mount_apfs returned Operation not permitted. Grant Full Disk Access to BorgBar, then restart the app."
        }
        if lower.contains("resource busy") {
            return "mount_apfs returned Resource busy. Wait a few seconds and retry; if it persists, reboot to clear stale mounts."
        }
        if joined.isEmpty {
            return "Snapshot mount failed with unknown error"
        }
        return joined
    }
}
