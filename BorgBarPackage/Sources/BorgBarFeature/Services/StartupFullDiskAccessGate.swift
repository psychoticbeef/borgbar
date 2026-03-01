import Foundation

@MainActor
struct StartupFullDiskAccessGate {
    let integration: StartupIntegrationPort

    func ensureFullDiskAccess(
        config: AppConfig,
        orchestrator: BackupOrchestrator,
        fullDiskAccessRequiredMessage: String
    ) async -> Bool {
        let firstCheck = await integration.fullDiskAccessDiagnostics()
        if firstCheck.granted {
            return true
        }
        // TCC updates can lag briefly after the user toggles access.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let secondCheck = await integration.fullDiskAccessDiagnostics()
        guard !secondCheck.granted else { return true }

        orchestrator.setIdleStatus(fullDiskAccessRequiredMessage)
        AppLogger.error(fullDiskAccessRequiredMessage)
        if let probeLine = failedProbeLine(from: secondCheck) {
            AppLogger.error(probeLine)
        }
        if shouldNotify(mode: config.preferences.notifications) {
            await integration.notify(
                title: "BorgBar Full Disk Access Needed",
                body: fullDiskAccessRequiredMessage
            )
        }
        await integration.promptForFullDiskAccessIfNeeded()

        // If the user grants access from the prompt path right away, continue startup.
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await integration.hasFullDiskAccess() {
                orchestrator.setIdleStatus("Full Disk Access granted")
                AppLogger.info("Full Disk Access granted after prompt")
                return true
            }
        }
        return false
    }

    private func failedProbeLine(from diagnostics: FullDiskAccessDiagnostics) -> String? {
        if let denied = diagnostics.probes.first(where: { $0.state == .permissionDenied }) {
            let detail = denied.detail ?? "permission denied"
            return "Full Disk Access probe blocked at \(denied.path): \(detail)"
        }
        if let errored = diagnostics.probes.first(where: { $0.state == .otherError }) {
            let detail = errored.detail ?? "unknown error"
            return "Full Disk Access probe error at \(errored.path): \(detail)"
        }
        return nil
    }

    private func shouldNotify(mode: NotificationMode) -> Bool {
        switch mode {
        case .none:
            return false
        case .errorsOnly, .all:
            return true
        }
    }
}
