import Foundation

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var config: AppConfig = .default
    @Published public var errorMessage: String?
    @Published public var helperHealth: HelperHealthStatus = .notInstalled
    @Published public var fullDiskAccessGranted = true
    @Published public var fullDiskAccessDiagnostics = FullDiskAccessDiagnostics(granted: true, probes: [])
    @Published public var passphraseStored = false
    @Published public var installingHelper = false

    private let store: ConfigStore
    private let installer: HelperInstallerService
    private let keychain: KeychainService
    private let fullDiskAccess: FullDiskAccessService
    private let fullDiskAccessRequiredMessage: String

    public init(
        store: ConfigStore = ConfigStore(),
        installer: HelperInstallerService = HelperInstallerService(),
        keychain: KeychainService = KeychainService(),
        fullDiskAccess: FullDiskAccessService = FullDiskAccessService(),
        fullDiskAccessRequiredMessage: String = BorgBarModel.fullDiskAccessRequiredMessage
    ) {
        self.store = store
        self.installer = installer
        self.keychain = keychain
        self.fullDiskAccess = fullDiskAccess
        self.fullDiskAccessRequiredMessage = fullDiskAccessRequiredMessage
    }

    public var timeMachineSubtitle: String {
        let version = config.repo.timeMachineExclusionOSVersion ?? "not scanned yet"
        if let scannedAt = config.repo.timeMachineExclusionScannedAt {
            return "Auto-detected on macOS \(version) at \(scannedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if !fullDiskAccessGranted {
            return "Auto-detection pending: Full Disk Access is required."
        }
        return "Auto-detection has not completed yet. Check Logs if this persists."
    }

    public var fullDiskAccessDiagnosticLines: [String] {
        let relevant = fullDiskAccessDiagnostics.probes.filter {
            $0.state == .permissionDenied || $0.state == .otherError
        }
        guard !relevant.isEmpty else {
            return ["No denied probe path captured yet."]
        }
        return relevant.prefix(4).map { probe in
            let detail = probe.detail ?? "no detail"
            return "[\(probe.state.rawValue)] \(probe.path) (\(detail))"
        }
    }

    public func load() async {
        if let loaded = try? await store.load() {
            config = loaded
            passphraseStored = await keychain.hasPassphrase(repoID: loaded.repo.id)
        }
        helperHealth = await installer.healthStatus()
        let diagnostics = await fullDiskAccess.diagnostics()
        fullDiskAccessDiagnostics = diagnostics
        fullDiskAccessGranted = diagnostics.granted
    }

    public func refreshPassphraseStored() async {
        passphraseStored = await keychain.hasPassphrase(repoID: config.repo.id)
    }

    public func save() async -> Bool {
        do {
            try await store.save(config)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func savePassphrase(_ passphrase: String) async -> Bool {
        do {
            try await keychain.setPassphrase(repoID: config.repo.id, passphrase: passphrase)
            passphraseStored = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func installHelper() async throws {
        installingHelper = true
        errorMessage = nil
        defer { installingHelper = false }
        try await installer.install()
        helperHealth = await installer.healthStatus()
    }

    public func recheckFullDiskAccess(orchestrator: BackupOrchestrator?) async {
        let diagnostics = await fullDiskAccess.diagnostics()
        fullDiskAccessDiagnostics = diagnostics
        fullDiskAccessGranted = diagnostics.granted
        syncFullDiskAccessStatus(orchestrator: orchestrator)
    }

    public func openFullDiskAccessSettings() {
        fullDiskAccess.openSystemSettings()
    }

    public func syncFullDiskAccessStatus(orchestrator: BackupOrchestrator?) {
        guard let orchestrator, !orchestrator.isRunning else { return }
        if fullDiskAccessGranted {
            if orchestrator.phase == .idle, orchestrator.statusMessage == fullDiskAccessRequiredMessage {
                orchestrator.setIdleStatus("Idle")
            }
            return
        }
        orchestrator.setIdleStatus(fullDiskAccessRequiredMessage)
    }
}
