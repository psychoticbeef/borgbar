import Foundation
import SwiftUI

@MainActor
public final class BorgBarModel: ObservableObject {
    public static let fullDiskAccessRequiredMessage = "Full Disk Access is required. Open System Settings > Privacy & Security > Full Disk Access and enable BorgBar."

    public let orchestrator: BackupOrchestrator
    private let scheduler: BackupScheduler
    private let startupCoordinator: StartupCoordinator
    private let fullDiskAccess = FullDiskAccessService()

    public init(
        orchestrator: BackupOrchestrator = BackupOrchestrator(),
        configStore: ConfigStore = ConfigStore(),
        startupCoordinator: StartupCoordinator? = nil
    ) {
        self.orchestrator = orchestrator
        self.scheduler = BackupScheduler(orchestrator: orchestrator, configStore: configStore)
        self.startupCoordinator = startupCoordinator ?? StartupCoordinator(configStore: configStore)

        do {
            try AppPaths().bootstrap()
            AppLogger.info("BorgBar launched (\(Bundle.main.bundlePath))")
        } catch {
            AppLogger.error("Directory bootstrap failed: \(error.localizedDescription)")
        }

        Task {
            await self.startupCoordinator.runStartup(
                orchestrator: orchestrator,
                fullDiskAccessRequiredMessage: Self.fullDiskAccessRequiredMessage
            )
        }
    }

    public func start() {
        scheduler.start()
    }

    public func refreshFullDiskAccessStatusForUI() async {
        guard !orchestrator.isRunning else { return }
        let diagnostics = await fullDiskAccess.diagnostics()
        if diagnostics.granted {
            if orchestrator.phase == .idle, orchestrator.statusMessage == Self.fullDiskAccessRequiredMessage {
                orchestrator.setIdleStatus("Idle")
            }
            return
        }
        orchestrator.setIdleStatus(Self.fullDiskAccessRequiredMessage)
    }
}
