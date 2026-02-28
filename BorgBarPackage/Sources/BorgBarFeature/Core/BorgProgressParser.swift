import Foundation

public struct BorgArchiveMetrics: Sendable {
    public var originalBytes: Int64
    public var compressedBytes: Int64
    public var deduplicatedBytes: Int64
    public var fileCount: Int

    public init(
        originalBytes: Int64,
        compressedBytes: Int64,
        deduplicatedBytes: Int64,
        fileCount: Int
    ) {
        self.originalBytes = originalBytes
        self.compressedBytes = compressedBytes
        self.deduplicatedBytes = deduplicatedBytes
        self.fileCount = fileCount
    }
}

public enum BorgProgressParser {
    public static func cacheCheckpointStatus(from line: String) -> String? {
        if line.contains("Saving files cache") {
            return "Checkpointing cache..."
        }
        if line.contains("Initializing cache transaction") {
            return "Checkpoint complete, resuming archive scan..."
        }
        return nil
    }

    public static func parseArchiveMetrics(_ line: String) -> BorgArchiveMetrics? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard
            let oIndex = tokens.firstIndex(of: "O"), oIndex >= 2,
            let cIndex = tokens.firstIndex(of: "C"), cIndex >= 2,
            let dIndex = tokens.firstIndex(of: "D"), dIndex >= 2,
            let nIndex = tokens.firstIndex(of: "N"), nIndex >= 1
        else {
            return nil
        }

        guard
            let original = parseBytes(value: tokens[oIndex - 2], unit: tokens[oIndex - 1]),
            let compressed = parseBytes(value: tokens[cIndex - 2], unit: tokens[cIndex - 1]),
            let deduplicated = parseBytes(value: tokens[dIndex - 2], unit: tokens[dIndex - 1]),
            let files = parseFileCount(tokens[nIndex - 1])
        else {
            return nil
        }

        return BorgArchiveMetrics(
            originalBytes: original,
            compressedBytes: compressed,
            deduplicatedBytes: deduplicated,
            fileCount: files
        )
    }

    public static func parseThroughput(_ line: String) -> String? {
        guard let range = line.range(of: #"[0-9]+(?:\.[0-9]+)?\s*[kMGTPE]?i?B/s"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range])
    }

    public static func parseETA(_ line: String) -> String? {
        guard let range = line.range(of: #"ETA\s+\S+"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range])
    }

    public static func humanBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    public static func rate(
        currentBytes: Int64,
        previousBytes: Int64?,
        currentTime: Date,
        previousTime: Date?
    ) -> Double? {
        guard let previousBytes, let previousTime else { return nil }
        let deltaBytes = currentBytes - previousBytes
        let deltaSeconds = currentTime.timeIntervalSince(previousTime)
        guard deltaBytes >= 0, deltaSeconds > 0 else { return nil }
        return Double(deltaBytes) / deltaSeconds
    }

    private static func parseBytes(value: String, unit: String) -> Int64? {
        guard let number = Double(value) else { return nil }
        let normalized = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let multiplier: Double
        switch normalized {
        case "b":
            multiplier = 1
        case "kb", "kib":
            multiplier = 1_024
        case "mb", "mib":
            multiplier = 1_024 * 1_024
        case "gb", "gib":
            multiplier = 1_024 * 1_024 * 1_024
        case "tb", "tib":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024
        case "pb", "pib":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024 * 1_024
        default:
            return nil
        }
        let bytes = number * multiplier
        if bytes.isFinite, bytes >= 0 {
            return Int64(bytes)
        }
        return nil
    }

    private static func parseFileCount(_ raw: String) -> Int? {
        let normalized = raw.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
        return Int(normalized)
    }
}
