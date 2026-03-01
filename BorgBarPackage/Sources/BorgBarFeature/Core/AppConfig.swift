import Foundation

public struct AppConfig: Codable, Sendable {
    public var version: Int
    public var repo: RepoConfig
    public var schedule: ScheduleConfig
    public var preferences: PreferencesConfig
    public var paths: PathsConfig

    public init(
        version: Int = 4,
        repo: RepoConfig,
        schedule: ScheduleConfig,
        preferences: PreferencesConfig = .init(),
        paths: PathsConfig = .init()
    ) {
        self.version = version
        self.repo = repo
        self.schedule = schedule
        self.preferences = preferences
        self.paths = paths
    }
}

public struct RepoConfig: Codable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var sshKeyPath: String
    public var compression: String
    public var enableSparseHandling: Bool
    public var maxRepositorySizeGiB: Int?
    public var includePaths: [String]
    public var userExcludePatterns: [String]
    public var userExcludeIfPresentMarkers: [String]
    public var commonSenseExcludePatterns: [String]
    public var userExcludeDirectoryContents: [String]
    public var timeMachineExcludedPaths: [String]
    public var timeMachineExclusionOSVersion: String?
    public var timeMachineExclusionScannedAt: Date?
    public var retention: RetentionConfig

    public init(
        id: String,
        name: String,
        path: String,
        sshKeyPath: String,
        compression: String = "zstd,3",
        enableSparseHandling: Bool = true,
        maxRepositorySizeGiB: Int? = nil,
        includePaths: [String],
        userExcludePatterns: [String],
        userExcludeIfPresentMarkers: [String] = [],
        commonSenseExcludePatterns: [String] = RepoConfig.defaultCommonSenseExcludePatterns,
        userExcludeDirectoryContents: [String] = [],
        timeMachineExcludedPaths: [String] = [],
        timeMachineExclusionOSVersion: String? = nil,
        timeMachineExclusionScannedAt: Date? = nil,
        retention: RetentionConfig
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sshKeyPath = sshKeyPath
        self.compression = compression
        self.enableSparseHandling = enableSparseHandling
        self.maxRepositorySizeGiB = maxRepositorySizeGiB
        self.includePaths = includePaths
        self.userExcludePatterns = userExcludePatterns
        self.userExcludeIfPresentMarkers = userExcludeIfPresentMarkers
        self.commonSenseExcludePatterns = commonSenseExcludePatterns
        self.userExcludeDirectoryContents = userExcludeDirectoryContents
        self.timeMachineExcludedPaths = timeMachineExcludedPaths
        self.timeMachineExclusionOSVersion = timeMachineExclusionOSVersion
        self.timeMachineExclusionScannedAt = timeMachineExclusionScannedAt
        self.retention = retention
    }

    public static let defaultCommonSenseExcludePatterns: [String] = [
        "*/Caches/*",
        "*/.Trash/*",
        "*/node_modules/*",
        "*/.build/*",
        "*/DerivedData/*",
        "*/.DS_Store",
        "*/nobackup/*"
    ]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case sshKeyPath
        case compression
        case enableSparseHandling
        case maxRepositorySizeGiB
        case includePaths
        case userExcludePatterns
        case userExcludeIfPresentMarkers
        case commonSenseExcludePatterns
        case userExcludeDirectoryContents
        case excludePatterns
        case excludeDirectoryContents
        case timeMachineExcludedPaths
        case timeMachineExclusionOSVersion
        case timeMachineExclusionScannedAt
        case retention
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        sshKeyPath = try container.decode(String.self, forKey: .sshKeyPath)
        compression = try container.decodeIfPresent(String.self, forKey: .compression) ?? "zstd,3"
        enableSparseHandling = try container.decodeIfPresent(Bool.self, forKey: .enableSparseHandling) ?? true
        maxRepositorySizeGiB = try container.decodeIfPresent(Int.self, forKey: .maxRepositorySizeGiB)
        includePaths = try container.decodeIfPresent([String].self, forKey: .includePaths) ?? ["~"]

        if let currentUserPatterns = try container.decodeIfPresent([String].self, forKey: .userExcludePatterns) {
            userExcludePatterns = currentUserPatterns
        } else {
            // Legacy v1 key held both defaults and user entries; keep only non-default items.
            let legacyPatterns = try container.decodeIfPresent([String].self, forKey: .excludePatterns) ?? []
            let defaultSet = Set(RepoConfig.defaultCommonSenseExcludePatterns)
            userExcludePatterns = legacyPatterns.filter { !defaultSet.contains($0) }
        }
        userExcludeIfPresentMarkers = try container.decodeIfPresent([String].self, forKey: .userExcludeIfPresentMarkers) ?? []

        commonSenseExcludePatterns = try container.decodeIfPresent([String].self, forKey: .commonSenseExcludePatterns)
            ?? RepoConfig.defaultCommonSenseExcludePatterns

        userExcludeDirectoryContents =
            try container.decodeIfPresent([String].self, forKey: .userExcludeDirectoryContents)
            ?? container.decodeIfPresent([String].self, forKey: .excludeDirectoryContents)
            ?? []

        timeMachineExcludedPaths = try container.decodeIfPresent([String].self, forKey: .timeMachineExcludedPaths) ?? []
        timeMachineExclusionOSVersion = try container.decodeIfPresent(String.self, forKey: .timeMachineExclusionOSVersion)
        timeMachineExclusionScannedAt = try container.decodeIfPresent(Date.self, forKey: .timeMachineExclusionScannedAt)
        retention = try container.decodeIfPresent(RetentionConfig.self, forKey: .retention) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(sshKeyPath, forKey: .sshKeyPath)
        try container.encode(compression, forKey: .compression)
        try container.encode(enableSparseHandling, forKey: .enableSparseHandling)
        try container.encodeIfPresent(maxRepositorySizeGiB, forKey: .maxRepositorySizeGiB)
        try container.encode(includePaths, forKey: .includePaths)
        try container.encode(userExcludePatterns, forKey: .userExcludePatterns)
        try container.encode(userExcludeIfPresentMarkers, forKey: .userExcludeIfPresentMarkers)
        try container.encode(commonSenseExcludePatterns, forKey: .commonSenseExcludePatterns)
        try container.encode(userExcludeDirectoryContents, forKey: .userExcludeDirectoryContents)
        try container.encode(timeMachineExcludedPaths, forKey: .timeMachineExcludedPaths)
        try container.encodeIfPresent(timeMachineExclusionOSVersion, forKey: .timeMachineExclusionOSVersion)
        try container.encodeIfPresent(timeMachineExclusionScannedAt, forKey: .timeMachineExclusionScannedAt)
        try container.encode(retention, forKey: .retention)
    }
}

public struct RetentionConfig: Codable, Sendable {
    public var keepHourly: Int
    public var keepDaily: Int
    public var keepWeekly: Int
    public var keepMonthly: Int

    public init(keepHourly: Int = 24, keepDaily: Int = 7, keepWeekly: Int = 4, keepMonthly: Int = 6) {
        self.keepHourly = keepHourly
        self.keepDaily = keepDaily
        self.keepWeekly = keepWeekly
        self.keepMonthly = keepMonthly
    }
}

public struct ScheduleConfig: Codable, Sendable {
    public var dailyTime: String
    public var wakeEnabled: Bool

    public init(dailyTime: String = "03:00", wakeEnabled: Bool = false) {
        self.dailyTime = dailyTime
        self.wakeEnabled = wakeEnabled
    }
}

public struct PreferencesConfig: Codable, Sendable {
    public var notifications: NotificationMode
    public var reachabilityProbe: Bool
    public var usePrivilegedSnapshotCommands: Bool
    public var launchAtLogin: Bool

    public init(
        notifications: NotificationMode = .all,
        reachabilityProbe: Bool = true,
        usePrivilegedSnapshotCommands: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.notifications = notifications
        self.reachabilityProbe = reachabilityProbe
        self.usePrivilegedSnapshotCommands = usePrivilegedSnapshotCommands
        self.launchAtLogin = launchAtLogin
    }

    private enum CodingKeys: String, CodingKey {
        case notifications
        case reachabilityProbe
        case usePrivilegedSnapshotCommands
        case launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try container.decodeIfPresent(NotificationMode.self, forKey: .notifications) ?? .all
        reachabilityProbe = try container.decodeIfPresent(Bool.self, forKey: .reachabilityProbe) ?? true
        usePrivilegedSnapshotCommands = try container.decodeIfPresent(Bool.self, forKey: .usePrivilegedSnapshotCommands) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notifications, forKey: .notifications)
        try container.encode(reachabilityProbe, forKey: .reachabilityProbe)
        try container.encode(usePrivilegedSnapshotCommands, forKey: .usePrivilegedSnapshotCommands)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
    }
}

public enum NotificationMode: String, Codable, Sendable, CaseIterable {
    case all
    case errorsOnly
    case none
}

public struct PathsConfig: Codable, Sendable {
    public var borgPath: String

    public init(borgPath: String = "/opt/homebrew/bin/borg") {
        self.borgPath = borgPath
    }
}

public extension AppConfig {
    static let `default` = AppConfig(
        repo: RepoConfig(
            id: "nas-main",
            name: "NAS Backup",
            path: "ssh://user@host/path",
            sshKeyPath: "~/.ssh/id_ed25519",
            includePaths: ["~"],
            userExcludePatterns: [],
            userExcludeIfPresentMarkers: [".nobackup"],
            retention: .init()
        ),
        schedule: .init()
    )
}
