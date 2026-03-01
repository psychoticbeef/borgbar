import Foundation

public struct RepositoryTrimSuggestion: Sendable {
    public let targetBytes: Int64
    public let currentBytes: Int64
    public let excessBytes: Int64
    public let estimatedFreedBytes: Int64
    public let projectedBytes: Int64
    public let archivesToDeleteOldestFirst: [String]
    public let analyzedArchiveCount: Int
    public let totalArchiveCount: Int
}

public actor BorgService {
    nonisolated private let runner: CommandRunner
    private static let createTimeoutSeconds: TimeInterval = 60 * 60 * 12
    private static let maintenanceTimeoutSeconds: TimeInterval = 60 * 60 * 2

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func createArchive(
        config: AppConfig,
        snapshotMount: String,
        passCommand: String,
        onProgressLine: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        let archiveName = archiveNamePrefix() + "-\(timestamp())"
        let args = BorgCreateCommandBuilder.buildArguments(
            config: config,
            snapshotMount: snapshotMount,
            archiveName: archiveName
        )

        let env = borgEnvironment(config: config, passCommand: passCommand)
        let result = try runner.runStreaming(
            executable: expanded(config.paths.borgPath),
            arguments: args,
            environment: env,
            timeoutSeconds: Self.createTimeoutSeconds,
            onLine: onProgressLine
        )
        let combinedOutput = result.stdout + "\n" + result.stderr
        if result.exitCode == 0 {
            return combinedOutput
        }
        // Borg uses exit code 1 for warnings. If archive summary is present, archive creation completed.
        if result.exitCode == 1, didCompleteArchive(in: combinedOutput) {
            AppLogger.info("borg create completed with warnings (exit 1), treating as success")
            return combinedOutput
        }
        throw BackupError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
    }

    public func prune(config: AppConfig, passCommand: String) throws -> String {
        let r = config.repo.retention
        let args = [
            "prune",
            "--keep-hourly", String(r.keepHourly),
            "--keep-daily", String(r.keepDaily),
            "--keep-weekly", String(r.keepWeekly),
            "--keep-monthly", String(r.keepMonthly)
        ]
        return try runMaintenanceOutput(config: config, passCommand: passCommand, arguments: args)
    }

    public func compact(config: AppConfig, passCommand: String) throws -> String {
        try runMaintenanceOutput(config: config, passCommand: passCommand, arguments: ["compact"])
    }

    public func repositorySizeBytes(config: AppConfig, passCommand: String) throws -> Int64? {
        // Prefer structured output to avoid fragile text parsing across Borg versions.
        let jsonResult = try runMaintenance(config: config, passCommand: passCommand, arguments: ["info", "--json"])
        if let value = BorgStatsParser.parseRepositorySizeBytesFromJSON(jsonResult.stdout) {
            return value
        }

        // Fallback: parse text output (or combined stream) for older formats.
        if let value = BorgStatsParser.parseRepositorySizeBytes(from: combinedOutput(from: jsonResult)) {
            return value
        }

        let textResult = try runMaintenance(config: config, passCommand: passCommand, arguments: ["info"])
        if let value = BorgStatsParser.parseRepositorySizeBytes(from: combinedOutput(from: textResult)) {
            return value
        }

        throw BackupError.commandFailed("Could not parse repository size from borg info output")
    }

    public func breakLock(
        config: AppConfig,
        passCommand: String,
        timeoutSeconds: TimeInterval? = nil
    ) throws {
        _ = try runMaintenance(
            config: config,
            passCommand: passCommand,
            arguments: ["break-lock"],
            timeoutSeconds: timeoutSeconds ?? Self.maintenanceTimeoutSeconds
        )
    }

    public func suggestTrimToTarget(
        config: AppConfig,
        passCommand: String,
        currentRepositoryBytes: Int64,
        targetRepositoryBytes: Int64
    ) throws -> RepositoryTrimSuggestion? {
        guard targetRepositoryBytes > 0, currentRepositoryBytes > targetRepositoryBytes else {
            return nil
        }

        let listResult = try runMaintenance(
            config: config,
            passCommand: passCommand,
            arguments: ["list", "--json", "--sort-by", "timestamp"]
        )
        let archiveNames = parseArchiveNamesFromListJSON(listResult.stdout)
        guard !archiveNames.isEmpty else {
            return nil
        }

        let excessBytes = currentRepositoryBytes - targetRepositoryBytes
        var estimatedFreedBytes: Int64 = 0
        var selectedArchives: [String] = []

        let analyzedNames = Array(archiveNames.prefix(50))
        for archiveName in analyzedNames {
            if estimatedFreedBytes >= excessBytes {
                break
            }
            let infoResult = try runMaintenance(
                config: config,
                passCommand: passCommand,
                arguments: ["info", "--json", "::\(archiveName)"]
            )
            guard let archiveDeduplicatedBytes = parseArchiveDeduplicatedBytesFromInfoJSON(infoResult.stdout) else {
                continue
            }
            selectedArchives.append(archiveName)
            estimatedFreedBytes += max(0, archiveDeduplicatedBytes)
        }

        guard !selectedArchives.isEmpty else {
            return nil
        }

        let projectedBytes = max(0, currentRepositoryBytes - estimatedFreedBytes)
        return RepositoryTrimSuggestion(
            targetBytes: targetRepositoryBytes,
            currentBytes: currentRepositoryBytes,
            excessBytes: excessBytes,
            estimatedFreedBytes: estimatedFreedBytes,
            projectedBytes: projectedBytes,
            archivesToDeleteOldestFirst: selectedArchives,
            analyzedArchiveCount: analyzedNames.count,
            totalArchiveCount: archiveNames.count
        )
    }

    nonisolated public func terminateActiveProcess() {
        runner.terminate()
    }

    private func borgEnvironment(config: AppConfig, passCommand: String) -> [String: String] {
        [
            "BORG_REPO": config.repo.path,
            "BORG_RSH": "ssh -i \(expanded(config.repo.sshKeyPath)) -o IdentitiesOnly=yes",
            "BORG_PASSCOMMAND": passCommand
        ]
    }

    private func expanded(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private func timestamp() -> String {
        let fmt = ISO8601DateFormatter()
        return fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private func archiveNamePrefix() -> String {
        Host.current().localizedName?.replacingOccurrences(of: " ", with: "-") ?? "mac"
    }

    private func didCompleteArchive(in output: String) -> Bool {
        output.contains("Archive fingerprint:") && output.contains("Time (end):")
    }

    private func runMaintenanceOutput(config: AppConfig, passCommand: String, arguments: [String]) throws -> String {
        let result = try runMaintenance(config: config, passCommand: passCommand, arguments: arguments)
        return combinedOutput(from: result)
    }

    private func runMaintenance(
        config: AppConfig,
        passCommand: String,
        arguments: [String],
        timeoutSeconds: TimeInterval? = nil
    ) throws -> CommandResult {
        let result = try runner.run(
            executable: expanded(config.paths.borgPath),
            arguments: arguments,
            environment: borgEnvironment(config: config, passCommand: passCommand),
            timeoutSeconds: timeoutSeconds ?? Self.maintenanceTimeoutSeconds
        )
        guard result.exitCode == 0 else {
            throw BackupError.commandFailed(errorOutput(from: result))
        }
        return result
    }

    private func combinedOutput(from result: CommandResult) -> String {
        result.stdout + "\n" + result.stderr
    }

    private func errorOutput(from result: CommandResult) -> String {
        result.stderr.isEmpty ? result.stdout : result.stderr
    }

    private func parseArchiveNamesFromListJSON(_ output: String) -> [String] {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BorgListPayload.self, from: data) else {
            return []
        }
        return payload.archives.map(\.name)
    }

    private func parseArchiveDeduplicatedBytesFromInfoJSON(_ output: String) -> Int64? {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BorgArchiveInfoPayload.self, from: data),
              let first = payload.archives.first else {
            return nil
        }
        return first.stats?.deduplicatedSize
    }
}

private struct BorgListPayload: Decodable {
    let archives: [BorgListArchive]
}

private struct BorgListArchive: Decodable {
    let name: String
}

private struct BorgArchiveInfoPayload: Decodable {
    let archives: [BorgArchiveInfo]
}

private struct BorgArchiveInfo: Decodable {
    let stats: BorgArchiveInfoStats?
}

private struct BorgArchiveInfoStats: Decodable {
    let deduplicatedSize: Int64?

    private enum CodingKeys: String, CodingKey {
        case deduplicatedSize = "deduplicated_size"
    }
}
