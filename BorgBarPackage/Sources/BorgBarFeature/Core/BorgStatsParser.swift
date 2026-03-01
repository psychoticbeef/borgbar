import Foundation

public struct BorgArchiveSummary: Sendable {
    public var thisArchiveOriginalBytes: Int64?
    public var thisArchiveDeduplicatedBytes: Int64?
    public var allArchivesDeduplicatedBytes: Int64?
}

public enum BorgStatsParser {
    public static func parseArchiveSummary(from output: String) -> BorgArchiveSummary {
        let thisArchive = captureThreeColumns(
            pattern: #"(?m)^This archive:\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s*$"#,
            in: output
        )
        let allArchives = captureThreeColumns(
            pattern: #"(?m)^All archives:\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s*$"#,
            in: output
        )

        return BorgArchiveSummary(
            thisArchiveOriginalBytes: parseHumanBytes(thisArchive?[0]),
            thisArchiveDeduplicatedBytes: parseHumanBytes(thisArchive?[2]),
            allArchivesDeduplicatedBytes: parseHumanBytes(allArchives?[2])
        )
    }

    public static func parseRepositorySizeBytes(from output: String) -> Int64? {
        let pattern = #"(?m)^Repository size:\s+((?:[0-9][0-9.,]*|Zero)\s*(?:[KMGTPE]i?)?B)\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            if let match = regex.firstMatch(in: output, range: range),
               match.numberOfRanges >= 2,
               let valueRange = Range(match.range(at: 1), in: output) {
                return parseHumanBytes(String(output[valueRange]))
            }
        }

        // Borg 1.x commonly omits "Repository size". Fall back to all-archives deduplicated bytes.
        return parseArchiveSummary(from: output).allArchivesDeduplicatedBytes
    }

    public static func parseRepositorySizeBytesFromJSON(_ output: String) -> Int64? {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BorgInfoPayload.self, from: data) else {
            return nil
        }

        // "unique_csize" best represents deduplicated repository data in storage.
        // Fall back to total compressed size when unique value is unavailable.
        return payload.cache?.stats?.uniqueCompressedSizeBytes ?? payload.cache?.stats?.totalCompressedSizeBytes
    }

    private static func captureThreeColumns(pattern: String, in output: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range), match.numberOfRanges >= 4 else {
            return nil
        }

        var values: [String] = []
        values.reserveCapacity(3)
        for index in 1...3 {
            guard let valueRange = Range(match.range(at: index), in: output) else { continue }
            values.append(String(output[valueRange]))
        }
        return values.count == 3 ? values : nil
    }

    static func parseHumanBytes(_ value: String?) -> Int64? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.lowercased().hasPrefix("zero") {
            return 0
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^([0-9][0-9.,]*)\s*((?:[KMGTPE]i?)?B)$"#
        ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value) else {
            return nil
        }

        var numberText = String(value[numberRange])
        if numberText.contains(",") && numberText.contains(".") {
            numberText = numberText.replacingOccurrences(of: ",", with: "")
        } else {
            numberText = numberText.replacingOccurrences(of: ",", with: ".")
        }

        guard let number = Double(numberText) else { return nil }
        let unit = String(value[unitRange]).uppercased()
        let multiplier: Double
        switch unit {
        case "B":
            multiplier = 1
        case "KB":
            multiplier = 1_000
        case "MB":
            multiplier = 1_000_000
        case "GB":
            multiplier = 1_000_000_000
        case "TB":
            multiplier = 1_000_000_000_000
        case "PB":
            multiplier = 1_000_000_000_000_000
        case "KIB":
            multiplier = 1_024
        case "MIB":
            multiplier = 1_048_576
        case "GIB":
            multiplier = 1_073_741_824
        case "TIB":
            multiplier = 1_099_511_627_776
        case "PIB":
            multiplier = 1_125_899_906_842_624
        default:
            return nil
        }
        return Int64((number * multiplier).rounded())
    }
}

private struct BorgInfoPayload: Decodable {
    let cache: BorgInfoCache?
}

private struct BorgInfoCache: Decodable {
    let stats: BorgInfoStats?
}

private struct BorgInfoStats: Decodable {
    let uniqueCompressedSizeBytes: Int64?
    let totalCompressedSizeBytes: Int64?

    private enum CodingKeys: String, CodingKey {
        case uniqueCompressedSizeBytes = "unique_csize"
        case totalCompressedSizeBytes = "total_csize"
    }
}
