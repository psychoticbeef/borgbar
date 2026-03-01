import Foundation

protocol TimeMachineDirectoryCollectorPort: Sendable {
    func collectRelevantDirectories(
        includePaths: [String],
        defaultPatterns: [String],
        isExcludedProbe: (String) -> Bool
    ) -> [String]
}

final class DefaultTimeMachineDirectoryCollectorPort: @unchecked Sendable, TimeMachineDirectoryCollectorPort {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func collectRelevantDirectories(
        includePaths: [String],
        defaultPatterns: [String],
        isExcludedProbe: (String) -> Bool
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
                isExcludedProbe: isExcludedProbe,
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
        isExcludedProbe: (String) -> Bool,
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
            if depth <= 2, isExcludedProbe(normalizedPath) {
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
