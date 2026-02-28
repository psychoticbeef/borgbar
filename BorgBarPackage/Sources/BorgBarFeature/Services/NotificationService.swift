import Foundation
import UserNotifications

public actor NotificationService {
    private var hasRequested = false

    public init() {}

    public func notify(title: String, body: String) async {
        if !hasRequested {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            hasRequested = true
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
