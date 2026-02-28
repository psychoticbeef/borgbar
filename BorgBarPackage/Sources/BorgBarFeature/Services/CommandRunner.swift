import Foundation

public struct CommandResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
}

public final class CommandRunner: @unchecked Sendable {
    private var process: Process?
    private let processLock = NSLock()

    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 3600
    ) throws -> CommandResult {
        try runStreaming(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeoutSeconds: timeoutSeconds,
            onLine: nil
        )
    }

    public func runStreaming(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 3600,
        onLine: (@Sendable (String) -> Void)?
    ) throws -> CommandResult {
        let process = Process()
        setProcess(process)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment {
            env[k] = v
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let collector = LineCollector(onLine: onLine)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.consume(handle.availableData, isStdout: true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.consume(handle.availableData, isStdout: false)
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            terminateProcessIfRunning(process)
            setProcess(nil)
            throw BackupError.commandFailed("Command timed out after \(Int(timeoutSeconds))s")
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        collector.consume(stdoutData, isStdout: true)
        collector.consume(stderrData, isStdout: false)
        let full = collector.fullBuffers()

        setProcess(nil)
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(bytes: full.stdout, encoding: .utf8) ?? "",
            stderr: String(bytes: full.stderr, encoding: .utf8) ?? ""
        )
    }

    public func terminate() {
        guard let process = currentProcess() else { return }
        terminateProcessIfRunning(process)
    }

    private func setProcess(_ process: Process?) {
        processLock.lock()
        self.process = process
        processLock.unlock()
    }

    private func currentProcess() -> Process? {
        processLock.lock()
        let value = process
        processLock.unlock()
        return value
    }

    private func terminateProcessIfRunning(_ process: Process) {
        guard process.isRunning else { return }

        let pid = process.processIdentifier
        signalDescendants(of: pid, signal: SIGTERM)
        process.terminate()
        Thread.sleep(forTimeInterval: 2)

        if process.isRunning {
            signalDescendants(of: pid, signal: SIGKILL)
            kill(pid, SIGKILL)
        } else {
            signalDescendants(of: pid, signal: SIGKILL)
        }
    }

    private func signalDescendants(of rootPID: Int32, signal: Int32) {
        for child in childPIDs(of: rootPID) {
            signalDescendants(of: child, signal: signal)
            kill(child, signal)
        }
    }

    private func childPIDs(of parentPID: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=", "-ppid", "\(parentPID)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: data, encoding: .utf8) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

private final class LineCollector: @unchecked Sendable {
    private var stdoutLineBuffer = Data()
    private var stderrLineBuffer = Data()
    private var fullStdout = Data()
    private var fullStderr = Data()
    private let outputLock = NSLock()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func consume(_ data: Data, isStdout: Bool) {
        guard !data.isEmpty else { return }
        outputLock.lock()
        defer { outputLock.unlock() }

        if isStdout {
            fullStdout.append(data)
            appendAndEmitLines(into: &stdoutLineBuffer, data: data)
        } else {
            fullStderr.append(data)
            appendAndEmitLines(into: &stderrLineBuffer, data: data)
        }
    }

    func fullBuffers() -> (stdout: Data, stderr: Data) {
        outputLock.lock()
        defer { outputLock.unlock() }
        return (fullStdout, fullStderr)
    }

    private func appendAndEmitLines(into buffer: inout Data, data: Data) {
        buffer.append(data)
        while let separator = nextSeparatorIndex(in: buffer) {
            let lineData = buffer.subdata(in: 0..<separator)
            let delimiter = buffer[separator]
            var removeUpperBound = separator
            if separator + 1 < buffer.count {
                let next = buffer[separator + 1]
                if (delimiter == 0x0D && next == 0x0A) || (delimiter == 0x0A && next == 0x0D) {
                    removeUpperBound = separator + 1
                }
            }
            buffer.removeSubrange(0...removeUpperBound)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                onLine?(line)
            }
        }
    }

    private func nextSeparatorIndex(in data: Data) -> Data.Index? {
        data.firstIndex { byte in
            byte == 0x0A || byte == 0x0D
        }
    }
}
