import Foundation
import Testing
@testable import BorgBarFeature

@Test func configValidationRejectsBadTime() async throws {
    let store = ConfigStore()
    var config = AppConfig.default
    config.schedule.dailyTime = "3pm"

    await #expect(throws: BackupError.self) {
        try await store.validate(config)
    }
}

@Test func configValidationRequiresHealthchecksURLWhenEnabled() async throws {
    let store = ConfigStore()
    var config = AppConfig.default
    config.preferences.healthchecksEnabled = true
    config.preferences.healthchecksPingURL = ""

    await #expect(throws: BackupError.self) {
        try await store.validate(config)
    }

    config.preferences.healthchecksPingURL = "https://hc-ping.com/1234"
    try await store.validate(config)
}

@Test func historyStoreKeepsMostRecentEntries() async throws {
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BorgBarTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let support = tempRoot.appendingPathComponent("Application Support/BorgBar", isDirectory: true)
    let logs = tempRoot.appendingPathComponent("Logs/BorgBar", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

    let paths = AppPathsForTests(appSupportDirectory: support, logsDirectory: logs)
    let store = HistoryStore(paths: paths.base)

    let old = BackupRunRecord(
        startedAt: Calendar.current.date(byAdding: .day, value: -120, to: Date())!,
        finishedAt: Date(),
        outcome: .success,
        summary: "old"
    )
    let recent = BackupRunRecord(
        startedAt: Date(),
        finishedAt: Date(),
        outcome: .success,
        summary: "new"
    )

    try await store.append(old)
    try await store.append(recent)

    let loaded = try await store.load()
    #expect(loaded.count == 1)
    #expect(loaded.first?.summary == "new")
}

@Test func borgProgressParserParsesArchiveMetrics() {
    let line = "1.25 GB O 500 MB C 120 MB D 12345 N"
    let parsed = BorgProgressParser.parseArchiveMetrics(line)
    #expect(parsed != nil)
    #expect(parsed?.fileCount == 12_345)
    #expect(parsed?.originalBytes == 1_342_177_280)
    #expect(parsed?.compressedBytes == 524_288_000)
    #expect(parsed?.deduplicatedBytes == 125_829_120)
}

@Test func borgProgressParserParsesCheckpointAndRates() {
    let checkpoint = BorgProgressParser.cacheCheckpointStatus(from: "Creating archive: Saving files cache")
    #expect(checkpoint == "Checkpointing cache...")

    let resumed = BorgProgressParser.cacheCheckpointStatus(from: "Initializing cache transaction: Reading files")
    #expect(resumed == "Checkpoint complete, resuming archive scan...")

    let t1 = Date(timeIntervalSince1970: 0)
    let t2 = Date(timeIntervalSince1970: 4)
    let rate = BorgProgressParser.rate(
        currentBytes: 4_096,
        previousBytes: 0,
        currentTime: t2,
        previousTime: t1
    )
    #expect(rate == 1024)
}

@Test func borgProgressParserParsesThroughputAndETA() {
    let line = "45.2MiB/s ETA 00:12"
    #expect(BorgProgressParser.parseThroughput(line) == "45.2MiB/s")
    #expect(BorgProgressParser.parseETA(line) == "ETA 00:12")
}

private struct AppPathsForTests {
    let base: AppPaths

    init(appSupportDirectory: URL, logsDirectory: URL) {
        base = AppPaths(
            appSupportDirectory: appSupportDirectory,
            logsDirectory: logsDirectory,
            configFile: appSupportDirectory.appendingPathComponent("app-config.json"),
            historyFile: appSupportDirectory.appendingPathComponent("history.json")
        )
    }
}
