import Foundation
import ServiceManagement

public enum HelperHealthStatus: Sendable {
    case healthy
    case notInstalled
    case unhealthy(String)
}

public actor HelperInstallerService {
    private let privilegedRunner: PrivilegedCommandRunner
    private let helperLabel: String
    private let appBundleURLProvider: @Sendable () -> URL

    public init(
        privilegedRunner: PrivilegedCommandRunner = PrivilegedCommandRunner(),
        helperLabel: String = PrivilegedHelperConstants.serviceName,
        appBundleURLProvider: @escaping @Sendable () -> URL = { Bundle.main.bundleURL }
    ) {
        self.privilegedRunner = privilegedRunner
        self.helperLabel = helperLabel
        self.appBundleURLProvider = appBundleURLProvider
    }

    public func isInstalled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperLabel).plist")
            switch service.status {
            case .enabled, .requiresApproval:
                return true
            case .notFound, .notRegistered:
                return false
            @unknown default:
                return false
            }
        }
        return false
    }

    public func healthStatus() async -> HelperHealthStatus {
        guard isInstalled() else {
            return .notInstalled
        }
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperLabel).plist")
            if service.status == .requiresApproval {
                return .unhealthy("Privileged helper requires approval in System Settings > Login Items.")
            }
        }

        do {
            let tmutilResult = try await privilegedRunner.run(
                executable: "/usr/bin/tmutil",
                arguments: ["listlocalsnapshotdates"],
                timeoutSeconds: 45
            )
            guard tmutilResult.exitCode == 0 else {
                let detail = (tmutilResult.stderr.isEmpty ? tmutilResult.stdout : tmutilResult.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .unhealthy("Privileged helper check failed: \(detail)")
            }

            let pmsetResult = try await privilegedRunner.run(
                executable: "/usr/bin/pmset",
                arguments: ["-g", "sched"],
                timeoutSeconds: 45
            )
            guard pmsetResult.exitCode == 0 else {
                let detail = (pmsetResult.stderr.isEmpty ? pmsetResult.stdout : pmsetResult.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .unhealthy("Privileged helper check failed: \(detail)")
            }

            return .healthy
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("not installed") {
                return .notInstalled
            }
            return .unhealthy("Privileged helper check failed: \(error.localizedDescription)")
        }
    }

    public func install() async throws {
        AppLogger.info("Helper install requested")
        guard #available(macOS 13.0, *) else {
            throw BackupError.snapshotFailed("Privileged helper installation requires macOS 13 or newer")
        }
        guard isRunningFromApplications() else {
            let path = appBundleURLProvider().path
            AppLogger.error("Helper install blocked: app is not running from Applications (\(path))")
            throw BackupError.snapshotFailed(
                "Install helper requires BorgBar to run from /Applications. " +
                "Move BorgBar.app to /Applications, relaunch it, then click Install Helper again."
            )
        }

        let status: SMAppService.Status
        do {
            status = try await MainActor.run {
                let service = SMAppService.daemon(plistName: "\(helperLabel).plist")
                let current = service.status
                if current == .enabled {
                    return current
                }
                try service.register()
                return service.status
            }
        } catch {
            let nsError = error as NSError
            let currentStatus = await MainActor.run { () -> SMAppService.Status in
                let service = SMAppService.daemon(plistName: "\(helperLabel).plist")
                return service.status
            }
            if currentStatus == .requiresApproval {
                await MainActor.run {
                    SMAppService.openSystemSettingsLoginItems()
                }
                AppLogger.error(
                    "Helper install requires approval (\(nsError.domain) \(nsError.code)): \(nsError.localizedDescription)"
                )
                throw BackupError.snapshotFailed(
                    "Helper installation needs approval in System Settings > General > Login Items."
                )
            }
            AppLogger.error(
                "Helper install failed (\(nsError.domain) \(nsError.code)): \(nsError.localizedDescription)"
            )
            throw BackupError.snapshotFailed(
                "Failed to install privileged helper (\(nsError.domain) \(nsError.code)): " +
                nsError.localizedDescription
            )
        }

        AppLogger.info("Helper install completed; service status: \(String(describing: status))")
        if status == .requiresApproval {
            await MainActor.run {
                SMAppService.openSystemSettingsLoginItems()
            }
            throw BackupError.snapshotFailed(
                "Helper installation needs approval in System Settings > General > Login Items."
            )
        }
        if status == .notRegistered || status == .notFound {
            throw BackupError.snapshotFailed("Privileged helper installation did not register correctly")
        }
    }

    private func isRunningFromApplications() -> Bool {
        let bundleURL = appBundleURLProvider().resolvingSymlinksInPath()
        let bundlePath = bundleURL.path
        let allowedPrefixes = [
            "/Applications/",
            NSHomeDirectory() + "/Applications/"
        ]
        return allowedPrefixes.contains(where: { bundlePath.hasPrefix($0) })
    }
}
