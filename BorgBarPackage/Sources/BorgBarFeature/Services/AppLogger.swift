import Foundation
import OSLog

public enum AppLogger {
    private enum Level: Int {
        case debug = 0
        case info = 1
        case error = 2
    }

    private static let logger = Logger(subsystem: "com.da.borgbar", category: "app")
    private static let minimumLevel = resolveMinimumLevel()

    public static func debug(_ message: String) {
        log(level: .debug, message: message)
    }

    public static func info(_ message: String) {
        log(level: .info, message: message)
    }

    public static func error(_ message: String) {
        log(level: .error, message: message)
    }

    private static func log(level: Level, message: String) {
        guard level.rawValue >= minimumLevel.rawValue else { return }
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
            writeToFile("DEBUG", message: message)
        case .info:
            logger.info("\(message, privacy: .public)")
            writeToFile("INFO", message: message)
        case .error:
            logger.error("\(message, privacy: .public)")
            writeToFile("ERROR", message: message)
        }
    }

    private static func resolveMinimumLevel() -> Level {
        guard let raw = ProcessInfo.processInfo.environment["BORGBAR_LOG_LEVEL"]?.lowercased() else {
            return .info
        }
        switch raw {
        case "debug":
            return .debug
        case "error":
            return .error
        default:
            return .info
        }
    }

    private static func writeToFile(_ level: String, message: String) {
        let dateFormatter = ISO8601DateFormatter()
        let paths = AppPaths()
        do {
            try paths.bootstrap()
            let logFile = paths.logsDirectory.appendingPathComponent("app.log")
            let line = "[\(dateFormatter.string(from: Date()))] [\(level)] \(message)\n"
            if FileManager.default.fileExists(atPath: logFile.path) {
                let handle = try FileHandle(forWritingTo: logFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                handle.write(Data(line.utf8))
            } else {
                try line.write(to: logFile, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to write app log: \(error.localizedDescription, privacy: .public)")
        }
    }
}
