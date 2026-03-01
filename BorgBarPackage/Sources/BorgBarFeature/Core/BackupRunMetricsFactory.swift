import Foundation

enum BackupRunMetricsFactory {
    static func completedRunMetrics(
        createOutput: String?,
        repositoryStoredBytes: Int64?,
        backupDuration: TimeInterval?,
        pruneDuration: TimeInterval?,
        compactDuration: TimeInterval?,
        startedAt: Date,
        finishedAt: Date
    ) -> BackupRunMetrics {
        let archiveSummary = createOutput.map { BorgStatsParser.parseArchiveSummary(from: $0) }
        return BackupRunMetrics(
            readFromSourceBytes: archiveSummary?.thisArchiveOriginalBytes,
            writtenToRepoBytes: archiveSummary?.thisArchiveDeduplicatedBytes,
            repositoryStoredBytes: repositoryStoredBytes,
            backupDurationSeconds: backupDuration,
            pruneDurationSeconds: pruneDuration,
            compactDurationSeconds: compactDuration,
            totalDurationSeconds: finishedAt.timeIntervalSince(startedAt)
        )
    }

    static func failedRunMetrics(
        startedAt: Date,
        finishedAt: Date,
        backupDuration: TimeInterval?,
        pruneDuration: TimeInterval?,
        compactDuration: TimeInterval?
    ) -> BackupRunMetrics {
        BackupRunMetrics(
            readFromSourceBytes: nil,
            writtenToRepoBytes: nil,
            repositoryStoredBytes: nil,
            backupDurationSeconds: backupDuration,
            pruneDurationSeconds: pruneDuration,
            compactDurationSeconds: compactDuration,
            totalDurationSeconds: finishedAt.timeIntervalSince(startedAt)
        )
    }
}
