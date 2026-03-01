import Foundation

enum BorgCreateCommandBuilder {
    private static let sparseChunkerParams = "fixed,1048576"

    static func buildArguments(
        config: AppConfig,
        snapshotMount: String,
        archiveName: String
    ) -> [String] {
        var args = [
            "create",
            "--progress",
            "--stats",
            "::\(archiveName)"
        ]

        args.append(contentsOf: ["--compression", config.repo.compression])
        args.append(contentsOf: ["--checkpoint-interval", "600"])
        if config.repo.enableSparseHandling {
            args.append("--sparse")
            args.append(contentsOf: ["--chunker-params", sparseChunkerParams])
        }

        let patternExclusions = Array(Set(config.repo.commonSenseExcludePatterns + config.repo.userExcludePatterns)).sorted()
        for pattern in patternExclusions {
            args.append(contentsOf: ["--exclude", pattern])
        }

        let markerExclusions = Set(
            config.repo.userExcludeIfPresentMarkers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        for marker in markerExclusions.sorted() {
            args.append(contentsOf: ["--exclude-if-present", marker])
        }

        for folder in Array(Set(config.repo.userExcludeDirectoryContents)).sorted() {
            let absolute = expanded(folder)
            let mountedFolder = snapshotMount + absolute
            // Exclude contents while keeping the directory entry itself.
            args.append(contentsOf: ["--exclude", "\(mountedFolder)/*"])
            args.append(contentsOf: ["--exclude", "\(mountedFolder)/.[!.]*"])
            args.append(contentsOf: ["--exclude", "\(mountedFolder)/..?*"])
        }

        let defaultPatterns = RepoConfig.defaultCommonSenseExcludePatterns
        for folder in Array(Set(config.repo.timeMachineExcludedPaths)).sorted() {
            let absolute = expanded(folder)
            let mountedFolder = snapshotMount + absolute
            guard !PathPatternMatcher.isCoveredByDefaultPatterns(path: mountedFolder, defaultPatterns: defaultPatterns) else {
                continue
            }
            args.append(contentsOf: ["--exclude", mountedFolder])
        }

        for include in config.repo.includePaths {
            let mounted = snapshotMount + expanded(include)
            args.append(mounted)
        }

        return args
    }

    private static func expanded(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }
}
