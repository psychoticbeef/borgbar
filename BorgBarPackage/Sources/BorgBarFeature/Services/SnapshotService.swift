import Foundation

public struct SnapshotRef: Sendable {
    public var snapshotName: String
    public var snapshotDate: String
    public var mountPoint: String
}

public protocol SnapshotService: Sendable {
    func createSnapshot(dailyTime: String) async throws -> SnapshotRef
    func mountSnapshot(_ snapshot: SnapshotRef) async throws
    func deleteSnapshot(_ snapshot: SnapshotRef, deleteLocalSnapshot: Bool) async
}

public actor LocalSnapshotService: SnapshotService {
    private let integration: LocalSnapshotIntegrationPort

    public init(
        privilegedRunner: PrivilegedCommandRunner = PrivilegedCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.integration = DefaultLocalSnapshotIntegrationPort(
            privilegedRunner: privilegedRunner,
            fileManager: fileManager
        )
    }

    init(integration: LocalSnapshotIntegrationPort) {
        self.integration = integration
    }

    public func createSnapshot(dailyTime: String) async throws -> SnapshotRef {
        let mountPoint = try integration.createMountDirectory()
        let referenceDate = integration.now()

        if let reusedDate = try await reusableSnapshotDate(referenceDate: referenceDate) {
            let reusedName = "com.apple.TimeMachine.\(reusedDate)"
            AppLogger.info("Reusing tracked BorgBar snapshot \(reusedName), mountpoint prepared at \(mountPoint)")
            return SnapshotRef(snapshotName: reusedName, snapshotDate: reusedDate, mountPoint: mountPoint)
        }

        let createResult = try await integration.runPrivileged(executable: "/usr/bin/tmutil", arguments: ["localsnapshot"])
        guard createResult.exitCode == 0 else {
            throw BackupError.snapshotFailed(createResult.stderr.isEmpty ? createResult.stdout : createResult.stderr)
        }

        let createOutput = [createResult.stdout, createResult.stderr].joined(separator: "\n")
        let snapshotDate = try await resolveSnapshotDate(afterCreateOutput: createOutput)
        guard !snapshotDate.isEmpty else {
            throw BackupError.snapshotFailed("Snapshot create returned success but no local snapshot is visible")
        }

        guard let retryUntil = DailySchedule.nextRunDate(from: dailyTime, referenceDate: referenceDate) else {
            throw BackupError.invalidConfig("schedule.dailyTime must be HH:mm")
        }

        let snapshotName = "com.apple.TimeMachine.\(snapshotDate)"
        try? integration.saveReuseState(snapshotDate: snapshotDate, createdAt: referenceDate, retryUntil: retryUntil)
        AppLogger.info("Created snapshot \(snapshotName), mountpoint prepared at \(mountPoint)")
        return SnapshotRef(snapshotName: snapshotName, snapshotDate: snapshotDate, mountPoint: mountPoint)
    }

    public func mountSnapshot(_ snapshot: SnapshotRef) async throws {
        let snapshotNames = ["\(snapshot.snapshotName).local", snapshot.snapshotName]
        let sources = candidateMountSources()

        let optionSets: [[String]] = [["-o", "ro"], ["-o", "nobrowse"], []]
        var lastFailures: [String] = []

        for attempt in 1...8 {
            var failures: [String] = []
            for snapshotName in snapshotNames {
                for source in sources {
                    for options in optionSets {
                        var args = options
                        args.append(contentsOf: ["-s", snapshotName, source, snapshot.mountPoint])
                        let result = try await integration.runPrivileged(
                            executable: "/sbin/mount_apfs",
                            arguments: args
                        )
                        if result.exitCode == 0 {
                            AppLogger.debug("Mounted snapshot \(snapshotName) from \(source) with args \(args.joined(separator: " "))")
                            return
                        }
                        let reason = result.stderr.isEmpty ? result.stdout : result.stderr
                        failures.append("snapshot=\(snapshotName) source=\(source) args=\(args.joined(separator: " ")): \(reason)")
                    }
                }
            }
            lastFailures = failures
            if attempt < 8, SnapshotMountFailureAnalyzer.shouldRetry(failures: failures) {
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }
            break
        }

        throw BackupError.mountFailed(SnapshotMountFailureAnalyzer.classify(failures: lastFailures))
    }

    public func deleteSnapshot(_ snapshot: SnapshotRef, deleteLocalSnapshot: Bool) async {
        _ = try? await integration.runPrivileged(executable: "/sbin/umount", arguments: [snapshot.mountPoint])
        if !deleteLocalSnapshot {
            AppLogger.debug("Preserving local snapshot \(snapshot.snapshotDate) after unsuccessful run")
            try? integration.removeItem(atPath: snapshot.mountPoint)
            return
        }

        if shouldKeepForReuse(snapshotDate: snapshot.snapshotDate, referenceDate: integration.now()) {
            AppLogger.debug("Keeping snapshot \(snapshot.snapshotDate) for reuse before scheduled cutoff")
            try? integration.removeItem(atPath: snapshot.mountPoint)
            return
        }

        _ = try? await integration.runPrivileged(executable: "/usr/bin/tmutil", arguments: ["deletelocalsnapshots", snapshot.snapshotDate])
        if let state = integration.loadReuseState(), state.snapshotDate == snapshot.snapshotDate {
            try? integration.clearReuseState()
        }
        try? integration.removeItem(atPath: snapshot.mountPoint)
    }

    public func cleanupStaleSnapshots() async {
        // Best-effort mount directory cleanup from interrupted runs.
        if let entries = try? integration.temporaryEntries() {
            for entry in entries where entry.hasPrefix("borgbar-snapshot-") {
                let path = "/tmp/\(entry)"
                _ = try? await integration.runPrivileged(executable: "/sbin/umount", arguments: [path])
                try? integration.removeItem(atPath: path)
            }
        }

        await cleanupReuseStateIfNeeded()
    }

    private func reusableSnapshotDate(referenceDate: Date) async throws -> String? {
        guard let state = integration.loadReuseState() else { return nil }

        if referenceDate >= state.retryUntil {
            let cutoffText = state.retryUntil.formatted(date: .abbreviated, time: .shortened)
            AppLogger.info("Tracked reusable snapshot \(state.snapshotDate) expired at \(cutoffText); deleting it before next run")
            await deleteTrackedSnapshot(snapshotDate: state.snapshotDate)
            try? integration.clearReuseState()
            return nil
        }

        if let dates = try? await listSnapshotDates() {
            guard dates.contains(state.snapshotDate) else {
                AppLogger.debug("Tracked reusable snapshot \(state.snapshotDate) no longer exists; clearing reuse state")
                try? integration.clearReuseState()
                return nil
            }
        } else {
            AppLogger.debug("Could not verify reusable snapshot via tmutil; keeping tracked reuse state for \(state.snapshotDate)")
        }

        return state.snapshotDate
    }

    private func resolveSnapshotDate(afterCreateOutput output: String) async throws -> String {
        if let parsed = SnapshotDateParser.parseSnapshotDate(from: output) {
            return parsed
        }

        var lastError = "no output"
        for _ in 0..<8 {
            do {
                let dates = try await listSnapshotDates()
                if let latest = dates.sorted().last {
                    return latest
                }
            } catch {
                lastError = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        throw BackupError.snapshotFailed("Snapshot create returned success but no local snapshot is visible (\(lastError))")
    }

    private func listSnapshotDates() async throws -> [String] {
        let argumentSets: [[String]] = [
            ["listlocalsnapshotdates"],
            ["listlocalsnapshotdates", "/System/Volumes/Data"]
        ]

        var errors: [String] = []
        for args in argumentSets {
            let result = try await integration.runPrivileged(
                executable: "/usr/bin/tmutil",
                arguments: args
            )
            if result.exitCode != 0 {
                errors.append(result.stderr.isEmpty ? result.stdout : result.stderr)
                continue
            }
            let output = [result.stdout, result.stderr].joined(separator: "\n")
            let dates = SnapshotDateParser.extractSnapshotDates(from: output)
            if !dates.isEmpty {
                return dates
            }
            AppLogger.debug("tmutil returned no parseable snapshot dates for args \(args.joined(separator: " ")); output=\(output)")
        }

        throw BackupError.snapshotFailed(errors.joined(separator: " | "))
    }

    private func candidateMountSources() -> [String] {
        var values = ["/System/Volumes/Data", "/"]
        if let dataDevice = try? resolveDevice(path: "/System/Volumes/Data") {
            values.append(dataDevice)
        }
        if let rootDevice = try? resolveDevice(path: "/") {
            values.append(rootDevice)
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func resolveDevice(path: String) throws -> String {
        let result = try integration.runCommand(executable: "/bin/df", arguments: ["-P", path], timeoutSeconds: 8)
        guard result.exitCode == 0 else {
            throw BackupError.mountFailed("Unable to resolve device for \(path)")
        }
        let lines = result.stdout.split(separator: "\n")
        guard lines.count >= 2 else {
            throw BackupError.mountFailed("Unexpected df output for \(path)")
        }
        let fields = lines[1].split(whereSeparator: \.isWhitespace)
        guard let device = fields.first else {
            throw BackupError.mountFailed("Failed to parse df output for \(path)")
        }
        return String(device)
    }

    private func shouldKeepForReuse(snapshotDate: String, referenceDate: Date) -> Bool {
        guard let state = integration.loadReuseState() else {
            return false
        }
        return state.snapshotDate == snapshotDate && referenceDate < state.retryUntil
    }

    private func cleanupReuseStateIfNeeded() async {
        guard let state = integration.loadReuseState() else { return }
        let referenceDate = integration.now()
        if let dates = try? await listSnapshotDates(), !dates.contains(state.snapshotDate) {
            AppLogger.debug("Clearing reuse state; tracked snapshot \(state.snapshotDate) is missing")
            try? integration.clearReuseState()
            return
        }
        guard referenceDate >= state.retryUntil else { return }

        let cutoffText = state.retryUntil.formatted(date: .abbreviated, time: .shortened)
        AppLogger.info("Retry window ended at \(cutoffText); deleting tracked snapshot \(state.snapshotDate)")
        await deleteTrackedSnapshot(snapshotDate: state.snapshotDate)
        try? integration.clearReuseState()
    }

    private func deleteTrackedSnapshot(snapshotDate: String) async {
        _ = try? await integration.runPrivileged(
            executable: "/usr/bin/tmutil",
            arguments: ["deletelocalsnapshots", snapshotDate]
        )
    }

}
