import Foundation

enum SettingsPresentationPolicy {
    static func timeMachineSubtitle(
        osVersion: String?,
        scannedAt: Date?,
        fullDiskAccessGranted: Bool
    ) -> String {
        let version = osVersion ?? "not scanned yet"
        if let scannedAt {
            return "Auto-detected on macOS \(version) at \(scannedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if !fullDiskAccessGranted {
            return "Auto-detection pending: Full Disk Access is required."
        }
        return "Auto-detection has not completed yet. Check Logs if this persists."
    }

    static func fullDiskAccessDiagnosticLines(from diagnostics: FullDiskAccessDiagnostics) -> [String] {
        let relevant = diagnostics.probes.filter {
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

    static func desiredIdleStatus(
        isOrchestratorRunning: Bool,
        orchestratorPhase: BackupPhase,
        orchestratorStatusMessage: String,
        fullDiskAccessGranted: Bool,
        fullDiskAccessRequiredMessage: String
    ) -> String? {
        guard !isOrchestratorRunning else { return nil }
        if fullDiskAccessGranted {
            if orchestratorPhase == .idle, orchestratorStatusMessage == fullDiskAccessRequiredMessage {
                return "Idle"
            }
            return nil
        }
        return fullDiskAccessRequiredMessage
    }
}
