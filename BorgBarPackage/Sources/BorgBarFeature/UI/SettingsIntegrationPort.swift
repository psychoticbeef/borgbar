import Foundation

@MainActor
protocol SettingsIntegrationPort: AnyObject {
    func loadConfig() async throws -> AppConfig
    func saveConfig(_ config: AppConfig) async throws
    func hasPassphrase(repoID: String) async -> Bool
    func setPassphrase(repoID: String, passphrase: String) async throws
    func helperHealthStatus() async -> HelperHealthStatus
    func installHelper() async throws
    func fullDiskAccessDiagnostics() async -> FullDiskAccessDiagnostics
    func openFullDiskAccessSettings()
    func launchAtLoginEnabled() async -> Bool
    func setLaunchAtLogin(enabled: Bool) async throws
}

@MainActor
final class DefaultSettingsIntegrationPort: SettingsIntegrationPort {
    private let store: ConfigStore
    private let installer: HelperInstallerService
    private let keychain: KeychainService
    private let fullDiskAccess: FullDiskAccessService
    private let launchAtLogin: LaunchAtLoginService

    init(
        store: ConfigStore = ConfigStore(),
        installer: HelperInstallerService = HelperInstallerService(),
        keychain: KeychainService = KeychainService(),
        fullDiskAccess: FullDiskAccessService = FullDiskAccessService(),
        launchAtLogin: LaunchAtLoginService = LaunchAtLoginService()
    ) {
        self.store = store
        self.installer = installer
        self.keychain = keychain
        self.fullDiskAccess = fullDiskAccess
        self.launchAtLogin = launchAtLogin
    }

    func loadConfig() async throws -> AppConfig {
        try await store.load()
    }

    func saveConfig(_ config: AppConfig) async throws {
        try await store.save(config)
    }

    func hasPassphrase(repoID: String) async -> Bool {
        await keychain.hasPassphrase(repoID: repoID)
    }

    func setPassphrase(repoID: String, passphrase: String) async throws {
        try await keychain.setPassphrase(repoID: repoID, passphrase: passphrase)
    }

    func helperHealthStatus() async -> HelperHealthStatus {
        await installer.healthStatus()
    }

    func installHelper() async throws {
        try await installer.install()
    }

    func fullDiskAccessDiagnostics() async -> FullDiskAccessDiagnostics {
        await fullDiskAccess.diagnostics()
    }

    func openFullDiskAccessSettings() {
        fullDiskAccess.openSystemSettings()
    }

    func launchAtLoginEnabled() async -> Bool {
        await launchAtLogin.isEnabled()
    }

    func setLaunchAtLogin(enabled: Bool) async throws {
        try await launchAtLogin.setEnabled(enabled)
    }
}
