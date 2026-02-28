import Foundation

struct SnapshotReuseStateStore {
    private let fileManager: FileManager
    private let stateFileURL: URL

    init(
        fileManager: FileManager = .default,
        stateFileURL: URL = AppPaths().appSupportDirectory.appendingPathComponent("snapshot-reuse-state.json")
    ) {
        self.fileManager = fileManager
        self.stateFileURL = stateFileURL
    }

    func load() -> SnapshotReuseState? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        return try? JSONDecoder().decode(SnapshotReuseState.self, from: data)
    }

    func save(snapshotDate: String, createdAt: Date, retryUntil: Date) throws {
        let state = SnapshotReuseState(snapshotDate: snapshotDate, createdAt: createdAt, retryUntil: retryUntil)
        let data = try JSONEncoder().encode(state)
        try fileManager.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: stateFileURL, options: [.atomic])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: stateFileURL.path) else { return }
        try fileManager.removeItem(at: stateFileURL)
    }
}

struct SnapshotReuseState: Codable {
    var snapshotDate: String
    var createdAt: Date
    var retryUntil: Date
}
