import Foundation
import SwiftUI

@MainActor
public final class BorgBarModel: ObservableObject {
    public static let fullDiskAccessRequiredMessage = "Full Disk Access is required. Open System Settings > Privacy & Security > Full Disk Access and enable BorgBar."

    public let orchestrator: BackupOrchestrator
    private let scheduler: BackupScheduler
    private let startupCoordinator: StartupCoordinator
    private let integration: BorgBarModelIntegrationPort

    public init(
        orchestrator: BackupOrchestrator = BackupOrchestrator(),
        configStore: ConfigStore = ConfigStore(),
        startupCoordinator: StartupCoordinator? = nil
    ) {
        self.orchestrator = orchestrator
        self.scheduler = BackupScheduler(orchestrator: orchestrator, configStore: configStore)
        let startupIntegration = DefaultStartupIntegrationPort(configStore: configStore)
        self.startupCoordinator = startupCoordinator ?? StartupCoordinator(integration: startupIntegration)
        self.integration = DefaultBorgBarModelIntegrationPort()

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

    init(
        orchestrator: BackupOrchestrator,
        configStore: ConfigStore,
        startupCoordinator: StartupCoordinator?,
        integration: BorgBarModelIntegrationPort
    ) {
        self.orchestrator = orchestrator
        self.scheduler = BackupScheduler(orchestrator: orchestrator, configStore: configStore)
        let startupIntegration = DefaultStartupIntegrationPort(configStore: configStore)
        self.startupCoordinator = startupCoordinator ?? StartupCoordinator(integration: startupIntegration)
        self.integration = integration

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
        let diagnostics = await integration.fullDiskAccessDiagnostics()
        if diagnostics.granted {
            if orchestrator.phase == .idle, orchestrator.statusMessage == Self.fullDiskAccessRequiredMessage {
                orchestrator.setIdleStatus("Idle")
            }
            return
        }
        orchestrator.setIdleStatus(Self.fullDiskAccessRequiredMessage)
    }
}
