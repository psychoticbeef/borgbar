import Foundation

public actor HealthcheckService {
    private let session: URLSession
    private let timeoutSeconds: TimeInterval

    public init(session: URLSession = .shared, timeoutSeconds: TimeInterval = 10) {
        self.session = session
        self.timeoutSeconds = timeoutSeconds
    }

    public func pingIfConfigured(config: AppConfig, event: HealthcheckPingEvent) async {
        guard config.preferences.healthchecksEnabled else { return }
        guard let endpoint = HealthcheckPingPlanner.endpoint(
            baseURLString: config.preferences.healthchecksPingURL,
            event: event
        ) else {
            AppLogger.error("Healthchecks ping skipped: invalid ping URL")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BackupError.commandFailed("Healthchecks request did not return HTTP response")
            }
            guard (200 ... 299).contains(http.statusCode) else {
                throw BackupError.commandFailed("Healthchecks request failed with status \(http.statusCode)")
            }
            AppLogger.debug("Healthchecks ping succeeded (\(event.debugDescription))")
        } catch {
            AppLogger.error("Healthchecks ping failed (\(event.debugDescription)): \(error.localizedDescription)")
        }
    }
}

private extension HealthcheckPingEvent {
    var debugDescription: String {
        switch self {
        case .start:
            return "start"
        case .success:
            return "success"
        case .fail:
            return "fail"
        }
    }
}
