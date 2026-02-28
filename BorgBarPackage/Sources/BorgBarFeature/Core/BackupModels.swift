import Foundation

public enum BackupPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case preflight
    case creatingSnapshot
    case mountingSnapshot
    case creatingArchive
    case pruning
    case compacting
    case cleanup
    case success
    case successWithWarning
    case failed
    case cancelled
}

public enum RunOutcome: String, Codable, Sendable {
    case success
    case successWithWarning
    case failed
    case cancelled
}

public struct ArchiveLiveStats: Sendable {
    public var originalBytes: Int64
    public var compressedBytes: Int64
    public var deduplicatedBytes: Int64
    public var fileCount: Int
    public var readRateBytesPerSecond: Double?
    public var writeRateBytesPerSecond: Double?
    public var throughputText: String?
    public var etaText: String?
    public var latestLine: String

    public init(
        originalBytes: Int64,
        compressedBytes: Int64,
        deduplicatedBytes: Int64,
        fileCount: Int,
        readRateBytesPerSecond: Double?,
        writeRateBytesPerSecond: Double?,
        throughputText: String?,
        etaText: String?,
        latestLine: String
    ) {
        self.originalBytes = originalBytes
        self.compressedBytes = compressedBytes
        self.deduplicatedBytes = deduplicatedBytes
        self.fileCount = fileCount
        self.readRateBytesPerSecond = readRateBytesPerSecond
        self.writeRateBytesPerSecond = writeRateBytesPerSecond
        self.throughputText = throughputText
        self.etaText = etaText
        self.latestLine = latestLine
    }
}

public struct BackupRunRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: RunOutcome
    public var failedPhase: BackupPhase?
    public var summary: String
    public var metrics: BackupRunMetrics?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        outcome: RunOutcome,
        failedPhase: BackupPhase? = nil,
        summary: String,
        metrics: BackupRunMetrics? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.failedPhase = failedPhase
        self.summary = summary
        self.metrics = metrics
    }
}

public struct BackupRunMetrics: Codable, Sendable {
    public var readFromSourceBytes: Int64?
    public var writtenToRepoBytes: Int64?
    public var repositoryStoredBytes: Int64?
    public var backupDurationSeconds: TimeInterval?
    public var pruneDurationSeconds: TimeInterval?
    public var compactDurationSeconds: TimeInterval?
    public var totalDurationSeconds: TimeInterval

    public init(
        readFromSourceBytes: Int64?,
        writtenToRepoBytes: Int64?,
        repositoryStoredBytes: Int64?,
        backupDurationSeconds: TimeInterval?,
        pruneDurationSeconds: TimeInterval?,
        compactDurationSeconds: TimeInterval?,
        totalDurationSeconds: TimeInterval
    ) {
        self.readFromSourceBytes = readFromSourceBytes
        self.writtenToRepoBytes = writtenToRepoBytes
        self.repositoryStoredBytes = repositoryStoredBytes
        self.backupDurationSeconds = backupDurationSeconds
        self.pruneDurationSeconds = pruneDurationSeconds
        self.compactDurationSeconds = compactDurationSeconds
        self.totalDurationSeconds = totalDurationSeconds
    }
}

public enum BackupError: LocalizedError, Sendable {
    case invalidConfig(String)
    case preflightFailed(String)
    case snapshotFailed(String)
    case mountFailed(String)
    case commandFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let msg):
            return "Invalid config: \(msg)"
        case .preflightFailed(let msg):
            return "Preflight failed: \(msg)"
        case .snapshotFailed(let msg):
            return "Snapshot failed: \(msg)"
        case .mountFailed(let msg):
            return "Snapshot mount failed: \(msg)"
        case .commandFailed(let msg):
            return "Backup command failed: \(msg)"
        case .cancelled:
            return "Backup was cancelled"
        }
    }
}
