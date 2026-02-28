import Foundation

public actor BorgService {
    nonisolated private let runner: CommandRunner
    private static let createTimeoutSeconds: TimeInterval = 60 * 60 * 12
    private static let maintenanceTimeoutSeconds: TimeInterval = 60 * 60 * 2
    private static let sparseChunkerParams = "fixed,1048576"

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
        var args = [
            "create",
            "--progress",
            "--stats",
            "::\(archiveName)"
        ]

        args.append(contentsOf: ["--compression", config.repo.compression])
        args.append(contentsOf: ["--checkpoint-interval", "600"])
        if config.repo.enableSparseHandling {
            args.append("--sparse")
            args.append(contentsOf: ["--chunker-params", Self.sparseChunkerParams])
        }

        let patternExclusions = Array(Set(config.repo.commonSenseExcludePatterns + config.repo.userExcludePatterns)).sorted()
        for pattern in patternExclusions {
            args.append(contentsOf: ["--exclude", pattern])
        }
        for folder in Array(Set(config.repo.userExcludeDirectoryContents)).sorted() {
            let absolute = expanded(folder)
            let mountedFolder = snapshotMount + absolute
            // Exclude contents while keeping the directory entry itself.
            args.append(contentsOf: ["--exclude", "\(mountedFolder)/*"])
            args.append(contentsOf: ["--exclude", "\(mountedFolder)/.[!.]*"])
            args.append(contentsOf: ["--exclude", "\(mountedFolder)/..?*"])
        }
        let defaultPatterns = RepoConfig.defaultCommonSenseExcludePatterns
        for folder in Array(Set(config.repo.timeMachineExcludedPaths)).sorted() {
            let absolute = expanded(folder)
            let mountedFolder = snapshotMount + absolute
            guard !isCoveredByDefaultPatterns(path: mountedFolder, defaultPatterns: defaultPatterns) else {
                continue
            }
            args.append(contentsOf: ["--exclude", mountedFolder])
        }

        for include in config.repo.includePaths {
            let relative = NSString(string: include).expandingTildeInPath
            let mounted = snapshotMount + relative
            args.append(mounted)
        }

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
        let result = try runMaintenance(config: config, passCommand: passCommand, arguments: ["info"])
        let output = combinedOutput(from: result)
        return BorgStatsParser.parseRepositorySizeBytes(from: output)
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

    private func isCoveredByDefaultPatterns(path: String, defaultPatterns: [String]) -> Bool {
        PathPatternMatcher.isCoveredByDefaultPatterns(path: path, defaultPatterns: defaultPatterns)
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
}
