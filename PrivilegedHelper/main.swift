import Foundation

final class PrivilegedHelperService: NSObject, NSXPCListenerDelegate, PrivilegedHelperXPCProtocol {
    private let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.serviceName)

    func run() {
        listener.delegate = self
        listener.resume()
        RunLoop.main.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func runCommand(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double,
        withReply reply: @escaping (Int, String, String) -> Void
    ) {
        guard let validationError = validate(executable: executable, arguments: arguments) else {
            reply(3, "", "arguments not allowed")
            return
        }
        guard validationError.isEmpty else {
            reply(3, "", validationError)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            reply(1, "", "failed to execute \(executable): \(error.localizedDescription)")
            return
        }

        let timeout = max(1, timeoutSeconds)
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            reply(1, "", "privileged command timed out after \(Int(timeout))s")
            return
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        reply(Int(process.terminationStatus), stdout, stderr)
    }

    private func validate(executable: String, arguments: [String]) -> String? {
        switch executable {
        case "/usr/bin/tmutil":
            return validateTMUtil(arguments: arguments)
        case "/sbin/mount_apfs":
            return validateMountAPFS(arguments: arguments)
        case "/sbin/umount":
            return validateUmount(arguments: arguments)
        case "/usr/bin/pmset":
            return validatePMSet(arguments: arguments)
        default:
            return "executable not allowed: \(executable)"
        }
    }

    private func validateTMUtil(arguments: [String]) -> String? {
        guard let command = arguments.first else {
            return "tmutil arguments not allowed"
        }
        if command == "localsnapshot", arguments.count == 1 {
            return ""
        }
        if command == "listlocalsnapshotdates", arguments.count == 1 || arguments.count == 2 {
            return ""
        }
        if command == "deletelocalsnapshots",
           arguments.count == 2,
           arguments[1].hasPrefix("20") {
            return ""
        }
        return "tmutil arguments not allowed"
    }

    private func validateMountAPFS(arguments: [String]) -> String? {
        // Caller supplies validated source/snapshot/mountpoint; enforce minimum structure.
        return arguments.count >= 5 ? "" : "mount_apfs arguments not allowed"
    }

    private func validateUmount(arguments: [String]) -> String? {
        return arguments.count == 1 ? "" : "umount arguments not allowed"
    }

    private func validatePMSet(arguments: [String]) -> String? {
        if arguments == ["-g", "sched"] {
            return ""
        }
        if arguments == ["repeat", "cancel"] {
            return ""
        }
        if arguments == ["schedule", "cancel"] {
            return ""
        }
        if arguments.count == 3,
           arguments[0] == "schedule",
           arguments[1] == "wakeorpoweron",
           isValidScheduleDateTime(arguments[2]) {
            return ""
        }
        return "pmset arguments not allowed"
    }

    private func isValidScheduleDateTime(_ value: String) -> Bool {
        // pmset expects "MM/dd/yy HH:mm:ss"
        let pattern = #"^\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

let service = PrivilegedHelperService()
service.run()
