import Foundation

public struct AppPaths {
    public let appSupportDirectory: URL
    public let logsDirectory: URL
    public let configFile: URL
    public let historyFile: URL

    public init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDirectory = base.appendingPathComponent("BorgBar", isDirectory: true)
        logsDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/BorgBar", isDirectory: true)
        configFile = appSupportDirectory.appendingPathComponent("app-config.json")
        historyFile = appSupportDirectory.appendingPathComponent("history.json")
    }

    public init(appSupportDirectory: URL, logsDirectory: URL, configFile: URL, historyFile: URL) {
        self.appSupportDirectory = appSupportDirectory
        self.logsDirectory = logsDirectory
        self.configFile = configFile
        self.historyFile = historyFile
    }

    public func bootstrap(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}
