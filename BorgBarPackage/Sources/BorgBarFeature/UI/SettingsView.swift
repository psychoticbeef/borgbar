import SwiftUI
import AppKit

@MainActor
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SettingsViewModel
    @State private var newExcludedFolder = ""
    @State private var newExcludePattern = ""
    @State private var newExcludeIfPresentMarker = ""
    @State private var passphrase = ""
    @State private var selectedSection: SettingsSection = .backupScope

    private let orchestrator: BackupOrchestrator?

    public init(orchestrator: BackupOrchestrator? = nil) {
        self.orchestrator = orchestrator
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selectedSection: $selectedSection)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("BorgBar Settings")
                        .font(.title3.weight(.semibold))

                    switch selectedSection {
                    case .backupScope:
                        BackupScopeSettingsSectionView(
                            viewModel: viewModel,
                            newExcludedFolder: $newExcludedFolder,
                            newExcludePattern: $newExcludePattern,
                            newExcludeIfPresentMarker: $newExcludeIfPresentMarker
                        )
                    case .repository:
                        RepositorySettingsSectionView(viewModel: viewModel)
                    case .security:
                        SecuritySettingsSectionView(
                            viewModel: viewModel,
                            passphrase: $passphrase,
                            onSavePassphrase: {
                                handleSavePassphrase()
                            },
                            onInstallHelper: {
                                handleInstallHelper()
                            }
                        )
                    case .permissions:
                        PermissionsSettingsSectionView(
                            viewModel: viewModel,
                            onOpenFullDiskAccess: viewModel.openFullDiskAccessSettings,
                            onRecheck: {
                                handleRecheckFullDiskAccess()
                            }
                        )
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    HStack {
                        Spacer()
                        Button("Save Changes") {
                            Task {
                                let saved = await viewModel.save()
                                if saved {
                                    dismiss()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 920, minHeight: 700)
        .task {
            await viewModel.load()
            viewModel.syncFullDiskAccessStatus(orchestrator: orchestrator)
        }
        .onChange(of: viewModel.config.repo.id) { _, _ in
            Task {
                await viewModel.refreshPassphraseStored()
            }
        }
        .onChange(of: viewModel.config.preferences.passphraseStorage) { _, _ in
            Task {
                await viewModel.refreshPassphraseStored()
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func handleSavePassphrase() {
        Task {
            let saved = await viewModel.savePassphrase(passphrase)
            if saved {
                passphrase = ""
            }
        }
    }

    private func handleInstallHelper() {
        Task {
            AppLogger.info("Install Helper button tapped")
            NSApp.activate(ignoringOtherApps: true)
            do {
                try await viewModel.installHelper()
                showAlert(title: "Helper Installed", message: "Privileged helper installation completed.")
            } catch {
                viewModel.errorMessage = "Install helper failed: \(error.localizedDescription)"
                showAlert(title: "Helper Install Failed", message: viewModel.errorMessage ?? "Unknown error")
            }
        }
    }

    private func handleRecheckFullDiskAccess() {
        Task {
            await viewModel.recheckFullDiskAccess(orchestrator: orchestrator)
        }
    }
}
