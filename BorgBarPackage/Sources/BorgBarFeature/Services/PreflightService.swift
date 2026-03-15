import Foundation

public enum PreflightService {
    private static let reachabilityRetryWindowSeconds: TimeInterval = 60
    private static let reachabilityRetryIntervalSeconds: TimeInterval = 5

    public static func run(
        config: AppConfig,
        keychain: KeychainService,
        onReachabilityRetry: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let integration = DefaultPreflightIntegrationPort(keychain: keychain)
        try await run(config: config, integration: integration, onReachabilityRetry: onReachabilityRetry)
    }

    static func run(
        config: AppConfig,
        integration: PreflightIntegrationPort,
        onReachabilityRetry: (@Sendable (String) -> Void)? = nil
    ) async throws {
        guard integration.isExecutableFile(atPath: expanded(config.paths.borgPath)) else {
            throw BackupError.preflightFailed("borg executable not found at \(config.paths.borgPath)")
        }

        guard integration.fileExists(atPath: expanded(config.repo.sshKeyPath)) else {
            throw BackupError.preflightFailed("SSH key not found at \(config.repo.sshKeyPath)")
        }

        let storageAvailability = await integration.passphraseStorageAvailability(config.preferences.passphraseStorage)
        guard storageAvailability.isAvailable else {
            throw BackupError.preflightFailed(
                storageAvailability.message ?? "Selected passphrase storage is unavailable"
            )
        }

        guard await integration.hasPassphrase(repoID: config.repo.id, storage: config.preferences.passphraseStorage) else {
            throw BackupError.preflightFailed(
                "Passphrase not found in \(config.preferences.passphraseStorage.keychainDisplayName) for repo \(config.repo.id)"
            )
        }

        if config.preferences.reachabilityProbe, let endpoint = parseSSHEndpoint(config.repo.path) {
            try await probeReachability(
                host: endpoint.host,
                port: endpoint.port,
                integration: integration,
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
        integration: PreflightIntegrationPort,
        onRetry: (@Sendable (String) -> Void)?
    ) async throws {
        var firstFailureAt: Date?
        var lastError = "unknown error"
        var attempt = 0

        while true {
            try Task.checkCancellation()
            attempt += 1

            do {
                let result = try integration.runReachabilityProbe(host: host, port: port)
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
