import Foundation
import ServiceManagement

public actor LaunchAtLoginService {
    public init() {}

    public func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        let service = SMAppService.mainApp
        if enabled && service.status == .enabled {
            return
        }
        if !enabled && service.status == .notRegistered {
            return
        }

        do {
            if enabled {
                try service.register()
                AppLogger.info("Launch at login enabled")
            } else {
                try service.unregister()
                AppLogger.info("Launch at login disabled")
            }
        } catch {
            throw BackupError.preflightFailed("Failed to update launch-at-login setting: \(error.localizedDescription)")
        }
    }
}
