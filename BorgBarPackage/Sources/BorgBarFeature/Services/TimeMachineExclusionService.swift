import Foundation

public actor TimeMachineExclusionService {
    private let runner: CommandRunner
    private let fileManager: FileManager
    private var traversalExclusionCache: [String: Bool] = [:]

    public init(
        runner: CommandRunner = CommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func refreshIfNeeded(config: AppConfig) throws -> (config: AppConfig, didUpdate: Bool) {
        let currentVersion = macOSVersionString()
        if config.repo.timeMachineExclusionOSVersion == currentVersion {
            return (config, false)
        }
        traversalExclusionCache.removeAll(keepingCapacity: true)

        let candidates = collectRelevantDirectories(
            includePaths: config.repo.includePaths,
            defaultPatterns: config.repo.commonSenseExcludePatterns
        )
        let excluded = try queryExcludedPaths(from: candidates)

        var updated = config
        updated.repo.timeMachineExcludedPaths = excluded
        updated.repo.timeMachineExclusionOSVersion = currentVersion
        updated.repo.timeMachineExclusionScannedAt = Date()
        return (updated, true)
    }

    private func macOSVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func collectRelevantDirectories(
        includePaths: [String],
        defaultPatterns: [String]
    ) -> [String] {
        let maxDepth = 3
        var paths = Set<String>()
        for include in includePaths {
            let root = expanded(include)
            guard isDirectory(root) else { continue }

            let normalizedRoot = normalized(root)
            if !isCoveredByDefaultPatterns(path: normalizedRoot, defaultPatterns: defaultPatterns) {
                paths.insert(normalizedRoot)
            }
            addDirectoriesRecursively(
                under: root,
                maxDepth: maxDepth,
                defaultPatterns: defaultPatterns,
                into: &paths
            )
        }
        AppLogger.info("Time Machine exclusion candidate directories: \(paths.count)")
        return paths.sorted()
    }

    private func addDirectoriesRecursively(
        under rootPath: String,
        maxDepth: Int,
        defaultPatterns: [String],
        into paths: inout Set<String>
    ) {
        var skippedCount = 0

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let rootDepth = rootURL.pathComponents.count
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in
                skippedCount += 1
                return true
            }
        ) else { return }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true else { continue }

            let depth = url.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if values?.isPackage == true {
                enumerator.skipDescendants()
            }

            let normalizedPath = normalized(url.path)
            if isCoveredByDefaultPatterns(path: normalizedPath, defaultPatterns: defaultPatterns) {
                enumerator.skipDescendants()
                continue
            }
            // Probe shallow directories and prune recursion for branches TM already excludes.
            if depth <= 2, isExcludedForTraversal(path: normalizedPath) {
                paths.insert(normalizedPath)
                enumerator.skipDescendants()
                continue
            }

            paths.insert(normalizedPath)
        }

        if skippedCount > 0 {
            AppLogger.info("Time Machine exclusion scan skipped \(skippedCount) unreadable paths under \(rootPath)")
        }
    }

    private func isExcludedForTraversal(path: String) -> Bool {
        if let cached = traversalExclusionCache[path] {
            return cached
        }
        do {
            let result = try runner.run(
                executable: "/usr/bin/tmutil",
                arguments: ["isexcluded", "-X", path],
                timeoutSeconds: 20
            )
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
            var args = ["isexcluded", "-X"]
            args.append(contentsOf: chunk)

            do {
                let result = try runner.run(
                    executable: "/usr/bin/tmutil",
                    arguments: args,
                    timeoutSeconds: 300
                )
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
                let result = try runner.run(
                    executable: "/usr/bin/tmutil",
                    arguments: ["isexcluded", "-X", path],
                    timeoutSeconds: 15
                )
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

    private func isCoveredByDefaultPatterns(path: String, defaultPatterns: [String]) -> Bool {
        PathPatternMatcher.isCoveredByDefaultPatterns(path: path, defaultPatterns: defaultPatterns)
    }

    private func expanded(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
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
