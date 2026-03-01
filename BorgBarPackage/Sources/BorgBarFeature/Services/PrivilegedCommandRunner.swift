import Foundation

public actor PrivilegedCommandRunner {
    private let serviceName: String

    public init(
        serviceName: String = PrivilegedHelperConstants.serviceName
    ) {
        self.serviceName = serviceName
    }

    public func run(executable: String, arguments: [String], timeoutSeconds: TimeInterval = 120) throws -> CommandResult {
        try runViaXPC(
            executable: executable,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runViaXPC(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) throws -> CommandResult {
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        connection.resume()
        defer {
            connection.invalidate()
        }

        let semaphore = DispatchSemaphore(value: 0)
        var proxyError: Error?
        var commandResult: CommandResult?
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            proxyError = error
            semaphore.signal()
        }

        guard let helper = proxy as? PrivilegedHelperXPCProtocol else {
            throw BackupError.snapshotFailed("Failed to connect to privileged helper service")
        }

        helper.runCommand(
            executable: executable,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        ) { exitCode, stdout, stderr in
            commandResult = CommandResult(exitCode: Int32(exitCode), stdout: stdout, stderr: stderr)
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 5)
        if waitResult == .timedOut {
            throw BackupError.snapshotFailed("Privileged helper command timed out")
        }
        if let proxyError {
            throw BackupError.snapshotFailed("Privileged helper connection failed: \(proxyError.localizedDescription)")
        }
        guard let commandResult else {
            throw BackupError.snapshotFailed("Privileged helper returned no result")
        }
        return commandResult
    }
}
