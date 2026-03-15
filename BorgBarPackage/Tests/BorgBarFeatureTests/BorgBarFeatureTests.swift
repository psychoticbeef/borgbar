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

@Test func configStoreMigratesLegacyDefaultBorgPath() async throws {
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BorgBarConfigTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let support = tempRoot.appendingPathComponent("Application Support/BorgBar", isDirectory: true)
    let logs = tempRoot.appendingPathComponent("Logs/BorgBar", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

    let paths = AppPathsForTests(appSupportDirectory: support, logsDirectory: logs)
    let store = ConfigStore(paths: paths.base)

    var legacyConfig = AppConfig.default
    legacyConfig.version = 4
    legacyConfig.paths.borgPath = PathsConfig.legacyDefaultBorgPath

    let encoder = JSONStoreCodec().encoder
    let data = try encoder.encode(legacyConfig)
    try data.write(to: paths.base.configFile, options: .atomic)

    let loaded = try await store.load()
    #expect(loaded.version == AppConfig.currentVersion)
    #expect(loaded.paths.borgPath == PathsConfig.defaultBorgPath)

    let reloadedData = try Data(contentsOf: paths.base.configFile)
    let decoded = try JSONStoreCodec().decoder.decode(AppConfig.self, from: reloadedData)
    #expect(decoded.version == AppConfig.currentVersion)
    #expect(decoded.paths.borgPath == PathsConfig.defaultBorgPath)
}

@Test func preferencesDefaultToNotificationsOffAndHealthchecksSuccessOnly() {
    let preferences = PreferencesConfig()
    #expect(preferences.notifications == .none)
    #expect(preferences.passphraseStorage == .localKeychain)
    #expect(!preferences.healthchecksEnabled)
    #expect(!preferences.healthchecksPingOnStart)
    #expect(!preferences.healthchecksPingOnError)
}

@Test func preferencesHealthcheckRoutingDefaultsToSuccessOnlyWhenEnabled() {
    var preferences = PreferencesConfig(
        healthchecksEnabled: true,
        healthchecksPingURL: "https://hc-ping.com/1234"
    )
    #expect(!preferences.shouldSendHealthcheck(for: .start))
    #expect(preferences.shouldSendHealthcheck(for: .success))
    #expect(!preferences.shouldSendHealthcheck(for: .fail(message: "oops")))

    preferences.healthchecksPingOnStart = true
    preferences.healthchecksPingOnError = true
    #expect(preferences.shouldSendHealthcheck(for: .start))
    #expect(preferences.shouldSendHealthcheck(for: .fail(message: "oops")))
}

@Test func localKeychainAvailabilityDoesNotRequireSpecialEntitlements() {
    let availability = KeychainService.availability(
        for: .localKeychain,
        entitlements: KeychainSigningEntitlements(
            applicationIdentifier: nil,
            teamIdentifier: nil,
            keychainAccessGroups: []
        )
    )

    #expect(availability == .available)
}

@Test func iCloudKeychainAvailabilityExplainsAdHocSigning() {
    let availability = KeychainService.availability(
        for: .iCloudKeychain,
        entitlements: KeychainSigningEntitlements(
            applicationIdentifier: nil,
            teamIdentifier: nil,
            keychainAccessGroups: []
        )
    )

    #expect(!availability.isAvailable)
    #expect(availability.message?.contains("ad hoc signed") == true)
}

@Test func iCloudKeychainAvailabilityRequiresAccessGroups() {
    let availability = KeychainService.availability(
        for: .iCloudKeychain,
        entitlements: KeychainSigningEntitlements(
            applicationIdentifier: "Q9QK5E2S4V.com.da.borgbar",
            teamIdentifier: "Q9QK5E2S4V",
            keychainAccessGroups: []
        )
    )

    #expect(!availability.isAvailable)
    #expect(availability.message?.contains("Keychain Access Groups") == true)
}

@Test func iCloudKeychainAvailabilitySucceedsWithTeamAndAccessGroup() {
    let availability = KeychainService.availability(
        for: .iCloudKeychain,
        entitlements: KeychainSigningEntitlements(
            applicationIdentifier: "Q9QK5E2S4V.com.da.borgbar",
            teamIdentifier: "Q9QK5E2S4V",
            keychainAccessGroups: ["Q9QK5E2S4V.com.da.borgbar"]
        )
    )

    #expect(availability == .available)
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
