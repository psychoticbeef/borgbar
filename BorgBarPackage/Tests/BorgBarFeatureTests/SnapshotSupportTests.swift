import Foundation
import Testing
@testable import BorgBarFeature

@Test func snapshotDateParserExtractsAndParsesDates() {
    let output = """
    Created local snapshot with date: 2026-02-28-093233
    Extra line 2026-02-28-101010
    """

    let extracted = SnapshotDateParser.extractSnapshotDates(from: output)
    #expect(extracted.count == 2)
    #expect(extracted.first == "2026-02-28-093233")
    #expect(SnapshotDateParser.parseSnapshotDate(from: output) == "2026-02-28-101010")
}

@Test func snapshotDateParserSameDayRespectsProvidedTimeZone() {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2026
    components.month = 2
    components.day = 28
    components.hour = 9
    let referenceDate = components.date!

    #expect(SnapshotDateParser.isSameDay(
        snapshotDate: "2026-02-28-093233",
        referenceDate: referenceDate,
        timeZone: TimeZone(secondsFromGMT: 0)!
    ))
    #expect(!SnapshotDateParser.isSameDay(
        snapshotDate: "2026-02-27-235959",
        referenceDate: referenceDate,
        timeZone: TimeZone(secondsFromGMT: 0)!
    ))
}

@Test func mountFailureAnalyzerClassifiesAndRetriesExpectedErrors() {
    let operationFailure = SnapshotMountFailureAnalyzer.classify(failures: ["mount_apfs: Operation not permitted"])
    #expect(operationFailure.contains("Grant Full Disk Access"))

    let busyFailure = SnapshotMountFailureAnalyzer.classify(failures: ["mount_apfs: Resource busy"])
    #expect(busyFailure.contains("Resource busy"))

    #expect(SnapshotMountFailureAnalyzer.shouldRetry(failures: ["resource busy"]))
    #expect(SnapshotMountFailureAnalyzer.shouldRetry(failures: ["No such file or directory"]))
    #expect(!SnapshotMountFailureAnalyzer.shouldRetry(failures: ["Operation not permitted"]))
}

@Test func snapshotReuseStateStoreRoundTripsAndClears() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("SnapshotReuseStateStoreTests-\(UUID().uuidString)", isDirectory: true)
    let stateFile = tempDir.appendingPathComponent("snapshot-reuse-state.json")
    let store = SnapshotReuseStateStore(fileManager: .default, stateFileURL: stateFile)
    let createdAt = Date(timeIntervalSince1970: 1234)
    let retryUntil = Date(timeIntervalSince1970: 5678)

    try store.save(snapshotDate: "2026-02-28-093233", createdAt: createdAt, retryUntil: retryUntil)
    let loaded = store.load()

    #expect(loaded?.snapshotDate == "2026-02-28-093233")
    #expect(loaded?.createdAt == createdAt)
    #expect(loaded?.retryUntil == retryUntil)

    try store.clear()
    #expect(store.load() == nil)
}
