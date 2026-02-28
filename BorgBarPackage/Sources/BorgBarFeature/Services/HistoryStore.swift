import Foundation

public actor HistoryStore {
    private let paths: AppPaths
    private let codec: JSONStoreCodec

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.codec = JSONStoreCodec()
    }

    public func load() throws -> [BackupRunRecord] {
        try paths.bootstrap()
        guard FileManager.default.fileExists(atPath: paths.historyFile.path) else {
            return []
        }

        let data = try Data(contentsOf: paths.historyFile)
        return try codec.decoder.decode([BackupRunRecord].self, from: data)
    }

    public func append(_ record: BackupRunRecord, keepDays: Int = 90) throws {
        let now = Date()
        var records = try load()
        records.append(record)

        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: now) ?? .distantPast
        records = records.filter { $0.startedAt >= cutoff }

        let data = try codec.encoder.encode(records.sorted(by: { $0.startedAt > $1.startedAt }))
        try data.write(to: paths.historyFile, options: .atomic)
    }
}
