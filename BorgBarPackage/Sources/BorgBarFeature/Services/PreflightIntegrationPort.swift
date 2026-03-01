import Foundation

protocol PreflightIntegrationPort: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
    func fileExists(atPath path: String) -> Bool
    func hasPassphrase(repoID: String) async -> Bool
    func runReachabilityProbe(host: String, port: Int) throws -> CommandResult
}

final class DefaultPreflightIntegrationPort: @unchecked Sendable, PreflightIntegrationPort {
    private let fileManager: FileManager
    private let keychain: KeychainService
    private let runner: CommandRunner

    init(
        fileManager: FileManager = .default,
        keychain: KeychainService,
        runner: CommandRunner = CommandRunner()
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        self.runner = runner
    }

    func isExecutableFile(atPath path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func hasPassphrase(repoID: String) async -> Bool {
        await keychain.hasPassphrase(repoID: repoID)
    }

    func runReachabilityProbe(host: String, port: Int) throws -> CommandResult {
        try runner.run(
            executable: "/usr/bin/nc",
            arguments: ["-z", "-G", "5", host, String(port)],
            timeoutSeconds: 8
        )
    }
}
