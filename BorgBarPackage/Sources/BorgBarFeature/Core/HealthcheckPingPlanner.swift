import Foundation

public enum HealthcheckPingEvent: Sendable {
    case start
    case success
    case fail(message: String?)
}

enum HealthcheckPingPlanner {
    static func endpoint(baseURLString: String, event: HealthcheckPingEvent) -> URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var baseURL = URL(string: trimmed) else {
            return nil
        }
        guard let scheme = baseURL.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }

        switch event {
        case .success:
            return baseURL
        case .start:
            return baseURL.appendingPathComponent("start")
        case .fail(let message):
            baseURL = baseURL.appendingPathComponent("fail")
            guard let message, !message.isEmpty else {
                return baseURL
            }
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return baseURL
            }
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "msg", value: message)]
            return components.url ?? baseURL
        }
    }
}
