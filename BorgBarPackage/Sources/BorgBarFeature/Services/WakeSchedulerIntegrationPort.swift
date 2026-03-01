import Foundation

protocol WakeSchedulerIntegrationPort: AnyObject, Sendable {
    func runPMSet(arguments: [String], timeoutSeconds: TimeInterval) async throws -> String
}

final class DefaultWakeSchedulerIntegrationPort: WakeSchedulerIntegrationPort, @unchecked Sendable {
    private let privilegedRunner: PrivilegedCommandRunner

    init(privilegedRunner: PrivilegedCommandRunner = PrivilegedCommandRunner()) {
        self.privilegedRunner = privilegedRunner
    }

    func runPMSet(arguments: [String], timeoutSeconds: TimeInterval = 30) async throws -> String {
        let result = try await privilegedRunner.run(
            executable: "/usr/bin/pmset",
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
        let detail = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            throw WakeSchedulerIntegrationError.commandFailed(
                "pmset \(arguments.joined(separator: " ")) failed (exit \(result.exitCode)): \(detail)"
            )
        }
        return detail
    }
}

private enum WakeSchedulerIntegrationError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return detail
        }
    }
}
