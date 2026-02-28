import Foundation

public actor PrivilegedCommandRunner {
    private let runner: CommandRunner
    private let helperPath: String

    public init(
        runner: CommandRunner = CommandRunner(),
        helperPath: String = "/usr/local/libexec/borgbar-helper"
    ) {
        self.runner = runner
        self.helperPath = helperPath
    }

    public func run(executable: String, arguments: [String], timeoutSeconds: TimeInterval = 120) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw BackupError.snapshotFailed(
                "Privileged helper is not installed. Open Settings and click Install Helper."
            )
        }

        let helperArgs = [executable] + arguments
        let result = try runner.run(
            executable: helperPath,
            arguments: helperArgs,
            timeoutSeconds: timeoutSeconds
        )
        return result
    }
}
