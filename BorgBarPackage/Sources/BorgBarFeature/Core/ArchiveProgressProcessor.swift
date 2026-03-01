import Foundation

struct ArchiveProgressProcessorState: Sendable {
    var lastSampleAt: Date?
    var lastOriginalBytes: Int64?
    var lastDeduplicatedBytes: Int64?
}

struct ArchiveProgressProcessorResult: Sendable {
    var state: ArchiveProgressProcessorState
    var stats: ArchiveLiveStats?
    var statusMessage: String?
}

enum ArchiveProgressProcessor {
    static func process(
        line: String,
        now: Date,
        currentStats: ArchiveLiveStats?,
        state: ArchiveProgressProcessorState
    ) -> ArchiveProgressProcessorResult? {
        if let checkpointStatus = BorgProgressParser.cacheCheckpointStatus(from: line) {
            return ArchiveProgressProcessorResult(
                state: state,
                stats: refreshedStats(
                    currentStats: currentStats,
                    latestLine: line,
                    throughputText: nil,
                    etaText: nil
                ),
                statusMessage: checkpointStatus
            )
        }

        if let parsed = BorgProgressParser.parseArchiveMetrics(line) {
            let readRate = BorgProgressParser.rate(
                currentBytes: parsed.originalBytes,
                previousBytes: state.lastOriginalBytes,
                currentTime: now,
                previousTime: state.lastSampleAt
            )
            let writeRate = BorgProgressParser.rate(
                currentBytes: parsed.deduplicatedBytes,
                previousBytes: state.lastDeduplicatedBytes,
                currentTime: now,
                previousTime: state.lastSampleAt
            )

            let nextState = ArchiveProgressProcessorState(
                lastSampleAt: now,
                lastOriginalBytes: parsed.originalBytes,
                lastDeduplicatedBytes: parsed.deduplicatedBytes
            )
            let stats = ArchiveLiveStats(
                originalBytes: parsed.originalBytes,
                compressedBytes: parsed.compressedBytes,
                deduplicatedBytes: parsed.deduplicatedBytes,
                fileCount: parsed.fileCount,
                readRateBytesPerSecond: readRate,
                writeRateBytesPerSecond: writeRate,
                throughputText: BorgProgressParser.parseThroughput(line),
                etaText: BorgProgressParser.parseETA(line),
                latestLine: line
            )
            let status = "Creating archive: \(BorgProgressParser.humanBytes(parsed.originalBytes)) read, \(BorgProgressParser.humanBytes(parsed.deduplicatedBytes)) written"
            return ArchiveProgressProcessorResult(state: nextState, stats: stats, statusMessage: status)
        }

        if line.contains("B/s") || line.contains("ETA") || line.localizedCaseInsensitiveContains("files") {
            let stats = refreshedStats(
                currentStats: currentStats,
                latestLine: line,
                throughputText: BorgProgressParser.parseThroughput(line),
                etaText: BorgProgressParser.parseETA(line)
            )
            return ArchiveProgressProcessorResult(
                state: state,
                stats: stats,
                statusMessage: "Creating archive: \(line)"
            )
        }

        return nil
    }

    private static func refreshedStats(
        currentStats: ArchiveLiveStats?,
        latestLine: String,
        throughputText: String?,
        etaText: String?
    ) -> ArchiveLiveStats? {
        guard let currentStats else { return nil }
        return ArchiveLiveStats(
            originalBytes: currentStats.originalBytes,
            compressedBytes: currentStats.compressedBytes,
            deduplicatedBytes: currentStats.deduplicatedBytes,
            fileCount: currentStats.fileCount,
            readRateBytesPerSecond: currentStats.readRateBytesPerSecond,
            writeRateBytesPerSecond: currentStats.writeRateBytesPerSecond,
            throughputText: throughputText ?? currentStats.throughputText,
            etaText: etaText ?? currentStats.etaText,
            latestLine: latestLine
        )
    }
}
