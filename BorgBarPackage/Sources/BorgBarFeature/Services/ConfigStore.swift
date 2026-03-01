import Foundation

public actor ConfigStore {
    private let paths: AppPaths
    private let codec: JSONStoreCodec

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.codec = JSONStoreCodec()
    }

    public func load() throws -> AppConfig {
        try paths.bootstrap()
        guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
            return .default
        }

        let data = try Data(contentsOf: paths.configFile)
        var config = try codec.decoder.decode(AppConfig.self, from: data)
        if needsLegacyRewrite(data: data) || config.version < 4 {
            config.version = max(config.version, 4)
            try save(config)
            AppLogger.info("Migrated app-config.json to latest schema")
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        try validate(config)
        try paths.bootstrap()
        let data = try codec.encoder.encode(config)
        try data.write(to: paths.configFile, options: .atomic)
    }

    public func validate(_ config: AppConfig) throws {
        guard !config.repo.id.isEmpty else {
            throw BackupError.invalidConfig("repo.id is required")
        }
        guard !config.repo.path.isEmpty else {
            throw BackupError.invalidConfig("repo.path is required")
        }
        guard !config.repo.sshKeyPath.isEmpty else {
            throw BackupError.invalidConfig("repo.sshKeyPath is required")
        }
        guard config.schedule.dailyTime.range(of: "^[0-2][0-9]:[0-5][0-9]$", options: .regularExpression) != nil else {
            throw BackupError.invalidConfig("schedule.dailyTime must be HH:mm")
        }
        if config.preferences.healthchecksEnabled {
            let raw = config.preferences.healthchecksPingURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                throw BackupError.invalidConfig("preferences.healthchecksPingURL is required when Healthchecks is enabled")
            }
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                throw BackupError.invalidConfig("preferences.healthchecksPingURL must be a valid http(s) URL")
            }
        }
    }

    private func needsLegacyRewrite(data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains("\"excludePatterns\"") || text.contains("\"excludeDirectoryContents\"")
    }
}
