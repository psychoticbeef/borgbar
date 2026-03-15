import Foundation

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var config: AppConfig = .default
    @Published public var errorMessage: String?
    @Published public var helperHealth: HelperHealthStatus = .notInstalled
    @Published public var fullDiskAccessGranted = true
    @Published public var fullDiskAccessDiagnostics = FullDiskAccessDiagnostics(granted: true, probes: [])
    @Published public var passphraseStored = false
    @Published public var passphraseStorageAvailabilityMessage: String?
    @Published public var installingHelper = false

    private let integration: SettingsIntegrationPort
    private let fullDiskAccessRequiredMessage: String

    public init(fullDiskAccessRequiredMessage: String = BorgBarModel.fullDiskAccessRequiredMessage) {
        self.integration = DefaultSettingsIntegrationPort()
        self.fullDiskAccessRequiredMessage = fullDiskAccessRequiredMessage
    }

    init(integration: SettingsIntegrationPort, fullDiskAccessRequiredMessage: String = BorgBarModel.fullDiskAccessRequiredMessage) {
        self.integration = integration
        self.fullDiskAccessRequiredMessage = fullDiskAccessRequiredMessage
    }

    public var timeMachineSubtitle: String {
        SettingsPresentationPolicy.timeMachineSubtitle(
            osVersion: config.repo.timeMachineExclusionOSVersion,
            scannedAt: config.repo.timeMachineExclusionScannedAt,
            fullDiskAccessGranted: fullDiskAccessGranted
        )
    }

    public var fullDiskAccessDiagnosticLines: [String] {
        SettingsPresentationPolicy.fullDiskAccessDiagnosticLines(from: fullDiskAccessDiagnostics)
    }

    public func load() async {
        if let loaded = try? await integration.loadConfig() {
            config = loaded
            await refreshPassphraseStored()
            config.preferences.launchAtLogin = await integration.launchAtLoginEnabled()
        }
        helperHealth = await integration.helperHealthStatus()
        let diagnostics = await integration.fullDiskAccessDiagnostics()
        fullDiskAccessDiagnostics = diagnostics
        fullDiskAccessGranted = diagnostics.granted
    }

    public func refreshPassphraseStored() async {
        let availability = await integration.passphraseStorageAvailability(config.preferences.passphraseStorage)
        passphraseStorageAvailabilityMessage = availability.message
        guard availability.isAvailable else {
            passphraseStored = false
            return
        }
        passphraseStored = await integration.hasPassphrase(
            repoID: config.repo.id,
            storage: config.preferences.passphraseStorage
        )
    }

    public func save() async -> Bool {
        if let message = passphraseStorageAvailabilityMessage,
           config.preferences.passphraseStorage == .iCloudKeychain {
            errorMessage = message
            return false
        }
        do {
            try await integration.saveConfig(config)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        do {
            try await integration.setLaunchAtLogin(enabled: config.preferences.launchAtLogin)
            return true
        } catch {
            errorMessage = "Settings saved, but launch-at-login update failed: \(error.localizedDescription)"
            return false
        }
    }

    public func savePassphrase(_ passphrase: String) async -> Bool {
        do {
            try await integration.setPassphrase(
                repoID: config.repo.id,
                passphrase: passphrase,
                storage: config.preferences.passphraseStorage
            )
            errorMessage = nil
            await refreshPassphraseStored()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func installHelper() async throws {
        installingHelper = true
        errorMessage = nil
        do {
            try await integration.installHelper()
        } catch {
            installingHelper = false
            throw error
        }
        installingHelper = false
        Task { [weak self] in
            guard let self else { return }
            let refreshed = await self.integration.helperHealthStatus()
            self.helperHealth = refreshed
        }
    }

    public func recheckFullDiskAccess(orchestrator: BackupOrchestrator?) async {
        let diagnostics = await integration.fullDiskAccessDiagnostics()
        fullDiskAccessDiagnostics = diagnostics
        fullDiskAccessGranted = diagnostics.granted
        syncFullDiskAccessStatus(orchestrator: orchestrator)
    }

    public func openFullDiskAccessSettings() {
        integration.openFullDiskAccessSettings()
    }

    public func syncFullDiskAccessStatus(orchestrator: BackupOrchestrator?) {
        guard let orchestrator else { return }
        if let desired = SettingsPresentationPolicy.desiredIdleStatus(
            isOrchestratorRunning: orchestrator.isRunning,
            orchestratorPhase: orchestrator.phase,
            orchestratorStatusMessage: orchestrator.statusMessage,
            fullDiskAccessGranted: fullDiskAccessGranted,
            fullDiskAccessRequiredMessage: fullDiskAccessRequiredMessage
        ) {
            orchestrator.setIdleStatus(desired)
        }
    }
}
