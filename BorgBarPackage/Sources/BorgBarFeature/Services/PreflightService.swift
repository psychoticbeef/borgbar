import Foundation

public enum PreflightService {
    private static let reachabilityRetryWindowSeconds: TimeInterval = 60
    private static let reachabilityRetryIntervalSeconds: TimeInterval = 5

    public static func run(
        config: AppConfig,
        keychain: KeychainService,
        onReachabilityRetry: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: expanded(config.paths.borgPath)) else {
            throw BackupError.preflightFailed("borg executable not found at \(config.paths.borgPath)")
        }

        guard fileManager.fileExists(atPath: expanded(config.repo.sshKeyPath)) else {
            throw BackupError.preflightFailed("SSH key not found at \(config.repo.sshKeyPath)")
        }

        guard await keychain.hasPassphrase(repoID: config.repo.id) else {
            throw BackupError.preflightFailed("Keychain item borgbar-repo-\(config.repo.id) is missing")
        }

        if config.preferences.reachabilityProbe, let endpoint = parseSSHEndpoint(config.repo.path) {
            try await probeReachability(
                host: endpoint.host,
                port: endpoint.port,
                onRetry: onReachabilityRetry
            )
        }
    }

    private static func expanded(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private static func parseSSHEndpoint(_ repoPath: String) -> (host: String, port: Int)? {
        guard repoPath.lowercased().hasPrefix("ssh://") else { return nil }
        guard let components = URLComponents(string: repoPath),
              let host = components.host else { return nil }
        return (host, components.port ?? 22)
    }

    private static func probeReachability(
        host: String,
        port: Int,
        onRetry: (@Sendable (String) -> Void)?
    ) async throws {
        let runner = CommandRunner()
        var firstFailureAt: Date?
        var lastError = "unknown error"
        var attempt = 0

        while true {
            try Task.checkCancellation()
            attempt += 1

            do {
                let result = try runner.run(
                    executable: "/usr/bin/nc",
                    arguments: ["-z", "-G", "5", host, String(port)],
                    timeoutSeconds: 8
                )
                if result.exitCode == 0 {
                    if attempt > 1 {
                        AppLogger.info("Reachability probe recovered for \(host):\(port) on attempt \(attempt)")
                    }
                    return
                }
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                lastError = message.isEmpty ? "nc exit code \(result.exitCode)" : message
            } catch {
                lastError = error.localizedDescription
            }

            let now = Date()
            if firstFailureAt == nil {
                firstFailureAt = now
            }
            let elapsed = now.timeIntervalSince(firstFailureAt ?? now)
            guard elapsed < reachabilityRetryWindowSeconds else {
                throw BackupError.preflightFailed(
                    "Reachability probe failed for \(host):\(port) after \(Int(elapsed.rounded()))s (\(lastError))"
                )
            }

            let remaining = max(1, Int(ceil(reachabilityRetryWindowSeconds - elapsed)))
            onRetry?("Reachability probe failed for \(host):\(port). Retrying for up to \(remaining)s.")

            let delay = min(reachabilityRetryIntervalSeconds, reachabilityRetryWindowSeconds - elapsed)
            let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }
}
