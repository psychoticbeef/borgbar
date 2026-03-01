import Foundation

@MainActor
public final class StartupCoordinator {
    private let integration: StartupIntegrationPort
    private let fullDiskAccessGate: StartupFullDiskAccessGate

    public init() {
        let integration = DefaultStartupIntegrationPort()
        self.integration = integration
        self.fullDiskAccessGate = StartupFullDiskAccessGate(integration: integration)
    }

    init(
        integration: StartupIntegrationPort,
        fullDiskAccessGate: StartupFullDiskAccessGate? = nil
    ) {
        self.integration = integration
        self.fullDiskAccessGate = fullDiskAccessGate ?? StartupFullDiskAccessGate(integration: integration)
    }

    public func runStartup(orchestrator: BackupOrchestrator, fullDiskAccessRequiredMessage: String) async {
        await orchestrator.loadHistory()
        await integration.cleanupStaleSnapshots()
        guard let loadedConfig = await loadOrCreateConfig() else { return }

        var startupIssues: [String] = []
        let hasFullDiskAccess = await ensureFullDiskAccess(
            config: loadedConfig,
            orchestrator: orchestrator,
            fullDiskAccessRequiredMessage: fullDiskAccessRequiredMessage
        )
        if !hasFullDiskAccess {
            startupIssues.append(fullDiskAccessRequiredMessage)
        }

        let config: AppConfig
        if hasFullDiskAccess {
            let refreshResult = await refreshTimeMachineExclusionsIfNeeded(
                config: loadedConfig,
                orchestrator: orchestrator,
                fullDiskAccessRequiredMessage: fullDiskAccessRequiredMessage
            )
            config = refreshResult.config
            if let issue = refreshResult.issueMessage {
                startupIssues.append(issue)
            }
        } else {
            AppLogger.info("Skipping Time Machine exclusion refresh until Full Disk Access is granted")
            config = loadedConfig
        }

        do {
            try await integration.syncLaunchAtLogin(for: config)
        } catch {
            let message = "Launch-at-login update failed: \(error.localizedDescription)"
            AppLogger.error(message)
            startupIssues.append(message)
        }

        await integration.updateWakeSchedule(for: config)
        if let helperIssue = await checkHelperHealth(config: config) {
            startupIssues.append(helperIssue)
        }
        applyStartupIssues(startupIssues, orchestrator: orchestrator)
    }

    private func loadOrCreateConfig() async -> AppConfig? {
        do {
            let config = try await integration.loadConfig()
            try await integration.validateConfig(config)
            return config
        } catch {
            do {
                backupExistingConfigIfPresent()
                let defaultConfig = AppConfig.default
                try await integration.saveConfig(defaultConfig)
                AppLogger.info("Wrote default app-config.json")
                return defaultConfig
            } catch {
                AppLogger.error("Failed to write default config: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func refreshTimeMachineExclusionsIfNeeded(
        config: AppConfig,
        orchestrator: BackupOrchestrator,
        fullDiskAccessRequiredMessage: String
    ) async -> (config: AppConfig, issueMessage: String?) {
        guard await integration.hasFullDiskAccess() else {
            orchestrator.setIdleStatus(fullDiskAccessRequiredMessage)
            AppLogger.info("Skipping Time Machine exclusion refresh until Full Disk Access is granted")
            return (config, fullDiskAccessRequiredMessage)
        }

        orchestrator.setIdleStatus("Refreshing Time Machine exclusions...")
        do {
            let result = try await integration.refreshTimeMachineExclusions(config: config)
            guard result.didUpdate else {
                orchestrator.setIdleStatus("Idle")
                return (config, nil)
            }

            let osVersion = result.config.repo.timeMachineExclusionOSVersion ?? "unknown"
            let count = result.config.repo.timeMachineExcludedPaths.count
            AppLogger.info("Refreshed Time Machine exclusions for macOS \(osVersion): \(count) paths")
            orchestrator.setIdleStatus("Time Machine exclusions refreshed (\(count) paths)")
            return (result.config, nil)
        } catch {
            let message = "Time Machine exclusions scan failed. Open Logs for details."
            AppLogger.error("Failed to refresh Time Machine exclusions: \(error.localizedDescription)")
            orchestrator.setIdleStatus(message)
            return (config, message)
        }
    }

    private func checkHelperHealth(config: AppConfig) async -> String? {
        let health = await integration.helperHealthStatus()
        let message: String
        switch health {
        case .healthy:
            return nil
        case .notInstalled:
            message = "Privileged helper is not installed. Open Settings and click Install Helper."
        case .unhealthy(let detail):
            message = detail
        }

        AppLogger.error(message)
        await notifyHelperIssueIfNeeded(mode: config.preferences.notifications, body: message)
        return message
    }

    private func applyStartupIssues(_ issues: [String], orchestrator: BackupOrchestrator) {
        let ordered = prioritizeIssues(issues)
        guard !ordered.isEmpty else { return }
        let combined = ordered.joined(separator: " | Also: ")
        if orchestrator.statusMessage != combined {
            orchestrator.setIdleStatus(combined)
        }
    }

    private func ensureFullDiskAccess(
        config: AppConfig,
        orchestrator: BackupOrchestrator,
        fullDiskAccessRequiredMessage: String
    ) async -> Bool {
        await fullDiskAccessGate.ensureFullDiskAccess(
            config: config,
            orchestrator: orchestrator,
            fullDiskAccessRequiredMessage: fullDiskAccessRequiredMessage
        )
    }

    private func notifyHelperIssueIfNeeded(mode: NotificationMode, body: String) async {
        guard shouldNotify(mode: mode) else { return }
        await integration.notify(title: "BorgBar Helper Attention Needed", body: body)
    }

    private func shouldNotify(mode: NotificationMode) -> Bool {
        switch mode {
        case .none:
            return false
        case .errorsOnly, .all:
            return true
        }
    }

    private func prioritizeIssues(_ issues: [String]) -> [String] {
        var unique: [String] = []
        for issue in issues where !issue.isEmpty {
            if !unique.contains(issue) {
                unique.append(issue)
            }
        }
        return unique.sorted { lhs, rhs in
            issuePriority(lhs) < issuePriority(rhs)
        }
    }

    private func issuePriority(_ issue: String) -> Int {
        if issue.localizedCaseInsensitiveContains("Full Disk Access") { return 0 }
        if issue.localizedCaseInsensitiveContains("Time Machine exclusions") { return 1 }
        if issue.localizedCaseInsensitiveContains("helper") { return 2 }
        return 3
    }

    private func backupExistingConfigIfPresent() {
        let fileManager = FileManager.default
        let configURL = AppPaths().configFile
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let backupURL = configURL.appendingPathExtension("bak")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: configURL, to: backupURL)
            AppLogger.info("Backed up app-config.json to app-config.json.bak before writing defaults")
        } catch {
            AppLogger.error("Failed to create config backup before defaults: \(error.localizedDescription)")
        }
    }

}
