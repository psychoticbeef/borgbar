import Foundation

protocol TimeMachineExclusionIntegrationPort: Sendable {
    func osVersionString() -> String
    func runIsExcluded(paths: [String], timeoutSeconds: TimeInterval) throws -> CommandResult
}

final class TMExclusionIntegrationAdapter: @unchecked Sendable, TimeMachineExclusionIntegrationPort {
    private let runner: CommandRunner

    init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    func runIsExcluded(paths: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        var args = ["isexcluded", "-X"]
        args.append(contentsOf: paths)
        return try runner.run(
            executable: "/usr/bin/tmutil",
            arguments: args,
            timeoutSeconds: timeoutSeconds
        )
    }
}
