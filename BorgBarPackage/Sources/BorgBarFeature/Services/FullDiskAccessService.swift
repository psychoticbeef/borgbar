import Foundation
import AppKit

public enum FullDiskAccessProbeState: String, Sendable {
    case accessible = "Accessible"
    case permissionDenied = "Permission denied"
    case missing = "Missing"
    case otherError = "Error"
}

public struct FullDiskAccessProbe: Sendable {
    public let path: String
    public let state: FullDiskAccessProbeState
    public let detail: String?

    public init(path: String, state: FullDiskAccessProbeState, detail: String?) {
        self.path = path
        self.state = state
        self.detail = detail
    }
}

public struct FullDiskAccessDiagnostics: Sendable {
    public let granted: Bool
    public let probes: [FullDiskAccessProbe]

    public init(granted: Bool, probes: [FullDiskAccessProbe]) {
        self.granted = granted
        self.probes = probes
    }
}

public actor FullDiskAccessService {
    private enum ProbeResult {
        case accessible
        case permissionDenied(String)
        case missing
        case otherError(String)
    }

    private let fileManager: FileManager
    private let runner: CommandRunner
    private let probePaths: [String]

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunner = CommandRunner()
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.probePaths = [
            "~/Library/Application Support/CloudDocs",
            "~/Library/Application Support/CallHistoryDB",
            "~/Library/Application Support/AddressBook",
            "~/Library/Application Support/com.apple.TCC",
            "~/Library/Mail",
            "~/Library/Messages",
            "~/Library/Safari",
            "~/Library/Calendars"
        ]
    }

    public func hasFullDiskAccess() -> Bool {
        diagnostics().granted
    }

    public func diagnostics() -> FullDiskAccessDiagnostics {
        let tmutil = tmutilProbeDiagnostic()
        if tmutil.state == .permissionDenied {
            return FullDiskAccessDiagnosticsEvaluator.evaluate(tmutilProbe: tmutil, pathProbes: [])
        }
        let pathProbes = fileProbeDiagnostics()
        return FullDiskAccessDiagnosticsEvaluator.evaluate(tmutilProbe: tmutil, pathProbes: pathProbes)
    }

    private func probeWithTmutil() -> ProbeResult {
        do {
            let home = expand("~")
            let result = try runner.run(
                executable: "/usr/bin/tmutil",
                arguments: ["isexcluded", "-X", home],
                timeoutSeconds: 12
            )
            if result.exitCode == 0 {
                return .accessible
            }
            let output = [result.stdout, result.stderr].joined(separator: "\n")
            if output.localizedCaseInsensitiveContains("requires Full Disk Access")
                || output.localizedCaseInsensitiveContains("Full Disk Access") {
                return .permissionDenied(output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            }
            return .otherError(output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
        } catch {
            return .otherError(error.localizedDescription)
        }
    }

    private func probe(path: String) -> ProbeResult {
        guard fileManager.fileExists(atPath: path) else {
            return .missing
        }

        do {
            if isDirectory(path) {
                _ = try fileManager.contentsOfDirectory(atPath: path).prefix(1)
            } else {
                _ = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
            }
            return .accessible
        } catch {
            if isPermissionError(error) {
                return .permissionDenied(error.localizedDescription)
            }
            return .otherError(error.localizedDescription)
        }
    }

    @MainActor
    public func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity"
        ]
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func expand(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        _ = fileManager.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileReadNoPermissionError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == EACCES || nsError.code == EPERM
        }
        return false
    }

    private func tmutilProbeDiagnostic() -> FullDiskAccessProbe {
        switch probeWithTmutil() {
        case .accessible:
            return FullDiskAccessProbe(path: "tmutil isexcluded -X ~", state: .accessible, detail: nil)
        case .permissionDenied(let detail):
            return FullDiskAccessProbe(path: "tmutil isexcluded -X ~", state: .permissionDenied, detail: detail)
        case .missing:
            return FullDiskAccessProbe(path: "tmutil isexcluded -X ~", state: .missing, detail: nil)
        case .otherError(let detail):
            return FullDiskAccessProbe(path: "tmutil isexcluded -X ~", state: .otherError, detail: detail)
        }
    }

    private func fileProbeDiagnostics() -> [FullDiskAccessProbe] {
        var probes: [FullDiskAccessProbe] = []
        probes.reserveCapacity(probePaths.count)

        for raw in probePaths {
            let expanded = expand(raw)
            switch probe(path: expanded) {
            case .accessible:
                probes.append(
                    FullDiskAccessProbe(path: expanded, state: .accessible, detail: nil)
                )
            case .permissionDenied(let detail):
                probes.append(
                    FullDiskAccessProbe(path: expanded, state: .permissionDenied, detail: detail)
                )
            case .missing:
                probes.append(
                    FullDiskAccessProbe(path: expanded, state: .missing, detail: nil)
                )
            case .otherError(let detail):
                AppLogger.debug("Full Disk Access probe warning for \(raw): \(detail)")
                probes.append(
                    FullDiskAccessProbe(path: expanded, state: .otherError, detail: detail)
                )
            }
        }

        return probes
    }
}
