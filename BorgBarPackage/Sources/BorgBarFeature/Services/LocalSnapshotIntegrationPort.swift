import Foundation

protocol LocalSnapshotIntegrationPort: Sendable {
    func now() -> Date
    func createMountDirectory() throws -> String
    func removeItem(atPath path: String) throws
    func temporaryEntries() throws -> [String]
    func runPrivileged(executable: String, arguments: [String]) async throws -> CommandResult
    func runCommand(executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult
    func loadReuseState() -> SnapshotReuseState?
    func saveReuseState(snapshotDate: String, createdAt: Date, retryUntil: Date) throws
    func clearReuseState() throws
}

final class DefaultLocalSnapshotIntegrationPort: @unchecked Sendable, LocalSnapshotIntegrationPort {
    private let privilegedRunner: PrivilegedCommandRunner
    private let runner: CommandRunner
    private let fileManager: FileManager
    private let reuseStateStore: SnapshotReuseStateStore
    private let nowProvider: @Sendable () -> Date

    init(
        privilegedRunner: PrivilegedCommandRunner = PrivilegedCommandRunner(),
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        let paths = AppPaths(fileManager: fileManager)
        self.privilegedRunner = privilegedRunner
        self.runner = CommandRunner()
        self.fileManager = fileManager
        self.reuseStateStore = SnapshotReuseStateStore(
            fileManager: fileManager,
            stateFileURL: paths.appSupportDirectory.appendingPathComponent("snapshot-reuse-state.json")
        )
        self.nowProvider = nowProvider
    }

    func now() -> Date {
        nowProvider()
    }

    func createMountDirectory() throws -> String {
        let mountPoint = "/tmp/borgbar-snapshot-\(UUID().uuidString.prefix(8))"
        try fileManager.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        return mountPoint
    }

    func removeItem(atPath path: String) throws {
        try fileManager.removeItem(atPath: path)
    }

    func temporaryEntries() throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: "/tmp")
    }

    func runPrivileged(executable: String, arguments: [String]) async throws -> CommandResult {
        try await privilegedRunner.run(executable: executable, arguments: arguments)
    }

    func runCommand(executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        try runner.run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds)
    }

    func loadReuseState() -> SnapshotReuseState? {
        reuseStateStore.load()
    }

    func saveReuseState(snapshotDate: String, createdAt: Date, retryUntil: Date) throws {
        try reuseStateStore.save(snapshotDate: snapshotDate, createdAt: createdAt, retryUntil: retryUntil)
    }

    func clearReuseState() throws {
        try reuseStateStore.clear()
    }
}
