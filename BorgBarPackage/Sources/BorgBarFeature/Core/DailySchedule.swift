import Foundation

enum DailySchedule {
    static func nextRunDate(from dailyTime: String, referenceDate: Date, calendar: Calendar = .current) -> Date? {
        let parts = dailyTime.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: referenceDate) else {
            return nil
        }
        if today > referenceDate {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }
}
