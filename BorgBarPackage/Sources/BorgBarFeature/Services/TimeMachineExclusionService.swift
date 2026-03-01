import Foundation

public actor TimeMachineExclusionService {
    private let integration: TimeMachineExclusionIntegrationPort
    private let directoryCollector: TimeMachineDirectoryCollectorPort
    private var traversalExclusionCache: [String: Bool] = [:]

    public init(
        runner: CommandRunner = CommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.integration = TMExclusionIntegrationAdapter(runner: runner)
        self.directoryCollector = DefaultTimeMachineDirectoryCollectorPort(fileManager: fileManager)
    }

    init(
        integration: TimeMachineExclusionIntegrationPort,
        directoryCollector: TimeMachineDirectoryCollectorPort = DefaultTimeMachineDirectoryCollectorPort()
    ) {
        self.integration = integration
        self.directoryCollector = directoryCollector
    }

    public func refreshIfNeeded(config: AppConfig) throws -> (config: AppConfig, didUpdate: Bool) {
        let currentVersion = integration.osVersionString()
        if config.repo.timeMachineExclusionOSVersion == currentVersion {
            return (config, false)
        }
        traversalExclusionCache.removeAll(keepingCapacity: true)

        let candidates = directoryCollector.collectRelevantDirectories(
            includePaths: config.repo.includePaths,
            defaultPatterns: config.repo.commonSenseExcludePatterns,
            isExcludedProbe: { path in
                self.isExcludedForTraversal(path: path)
            }
        )
        let excluded = try queryExcludedPaths(from: candidates)

        var updated = config
        updated.repo.timeMachineExcludedPaths = excluded
        updated.repo.timeMachineExclusionOSVersion = currentVersion
        updated.repo.timeMachineExclusionScannedAt = Date()
        return (updated, true)
    }

    private func isExcludedForTraversal(path: String) -> Bool {
        if let cached = traversalExclusionCache[path] {
            return cached
        }
        do {
            let result = try integration.runIsExcluded(paths: [path], timeoutSeconds: 20)
            guard result.exitCode == 0 else {
                traversalExclusionCache[path] = false
                return false
            }
            let excluded = parseExcludedPaths(plistXML: result.stdout).contains(normalized(path))
            traversalExclusionCache[path] = excluded
            return excluded
        } catch {
            AppLogger.debug("tmutil traversal probe failed for \(path): \(error.localizedDescription)")
            traversalExclusionCache[path] = false
            return false
        }
    }

    private func queryExcludedPaths(from candidates: [String]) throws -> [String] {
        guard !candidates.isEmpty else { return [] }

        var excluded = Set<String>()
        var successfulChunks = 0
        var failedChunks = 0
        var firstFailure: String?
        var failedPaths: [String] = []

        for chunk in candidates.chunked(into: 20) {
            do {
                let result = try integration.runIsExcluded(paths: chunk, timeoutSeconds: 300)
                guard result.exitCode == 0 else {
                    failedChunks += 1
                    failedPaths.append(contentsOf: chunk)
                    let output = result.stderr.isEmpty ? result.stdout : result.stderr
                    if firstFailure == nil {
                        firstFailure = output
                    }
                    continue
                }
                successfulChunks += 1
                excluded.formUnion(parseExcludedPaths(plistXML: result.stdout))
            } catch {
                failedChunks += 1
                failedPaths.append(contentsOf: chunk)
                if firstFailure == nil {
                    firstFailure = error.localizedDescription
                }
                AppLogger.debug("tmutil isexcluded chunk failed: \(error.localizedDescription)")
            }
        }

        if !failedPaths.isEmpty {
            let recovered = recoverExcludedPaths(from: failedPaths)
            if !recovered.isEmpty {
                excluded.formUnion(recovered)
                AppLogger.info("Recovered \(recovered.count) exclusions from failed tmutil chunks")
            }
        }

        if failedChunks > 0 {
            AppLogger.error("Time Machine exclusion scan had \(failedChunks) failed tmutil chunks and \(successfulChunks) successful chunks")
        }
        guard successfulChunks > 0 || !excluded.isEmpty else {
            throw BackupError.preflightFailed("tmutil isexcluded failed: \(firstFailure ?? "no successful chunks")")
        }
        return excluded.sorted()
    }

    private func recoverExcludedPaths(from paths: [String]) -> Set<String> {
        var recovered = Set<String>()
        let unique = Array(Set(paths)).sorted()
        for path in unique {
            do {
                let result = try integration.runIsExcluded(paths: [path], timeoutSeconds: 15)
                guard result.exitCode == 0 else { continue }
                let normalizedPath = normalized(path)
                if parseExcludedPaths(plistXML: result.stdout).contains(normalizedPath) {
                    recovered.insert(normalizedPath)
                }
            } catch {
                continue
            }
        }
        return recovered
    }

    private func parseExcludedPaths(plistXML: String) -> [String] {
        guard let data = plistXML.data(using: .utf8) else { return [] }
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let entries = plist as? [[String: Any]]
        else {
            return []
        }

        var result: [String] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            guard let excluded = entry["IsExcluded"] as? NSNumber, excluded.intValue != 0 else { continue }
            guard let path = entry["Path"] as? String else { continue }
            result.append(normalized(path))
        }
        return result
    }

    private func normalized(_ path: String) -> String {
        NSString(string: path).standardizingPath
    }

}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count / size) + 1)
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
