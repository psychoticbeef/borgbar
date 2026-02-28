import SwiftUI
import AppKit

@MainActor
public struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case backupScope = "Backup Scope"
        case repository = "Repository"
        case security = "Security"
        case permissions = "Permissions"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .backupScope:
                return "externaldrive.badge.timemachine"
            case .repository:
                return "externaldrive"
            case .security:
                return "key.fill"
            case .permissions:
                return "lock.shield"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SettingsViewModel
    @State private var newExcludedFolder = ""
    @State private var newExcludePattern = ""
    @State private var passphrase = ""
    @State private var selectedSection: SettingsSection = .backupScope

    private let orchestrator: BackupOrchestrator?

    public init(orchestrator: BackupOrchestrator? = nil) {
        self.orchestrator = orchestrator
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.systemImage)
                                    .frame(width: 14)
                                Text(section.rawValue)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSection == section ? Color.accentColor.opacity(0.16) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 240)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("BorgBar Settings")
                        .font(.title3.weight(.semibold))

                    switch selectedSection {
                    case .backupScope:
                        backupScopeSection
                    case .repository:
                        repositorySection
                    case .security:
                        securitySection
                    case .permissions:
                        permissionsSection
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
    }

    @ViewBuilder
    private var backupScopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            exclusionList(
                title: "User: Exclude Folder Contents",
                subtitle: "Keeps the folder, excludes children (example: ~/Downloads).",
                items: $viewModel.config.repo.userExcludeDirectoryContents,
                newValue: $newExcludedFolder,
                placeholder: "~/Downloads"
            )

            exclusionList(
                title: "User: Exclude Glob Patterns",
                subtitle: "Borg --exclude patterns (example: */venv/*).",
                items: $viewModel.config.repo.userExcludePatterns,
                newValue: $newExcludePattern,
                placeholder: "*/venv/*"
            )

            readOnlyList(
                title: "Common-Sense Exclusions",
                subtitle: "Built-in exclusions always applied.",
                items: viewModel.config.repo.commonSenseExcludePatterns,
                maxHeight: 150
            )

            readOnlyList(
                title: "Time Machine Exclusions",
                subtitle: viewModel.timeMachineSubtitle,
                items: viewModel.config.repo.timeMachineExcludedPaths,
                maxHeight: 300
            )
        }
    }

    @ViewBuilder
    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Repo Name", text: $viewModel.config.repo.name)
            TextField("Repository Path", text: $viewModel.config.repo.path)
            TextField("SSH Key Path", text: $viewModel.config.repo.sshKeyPath)
            TextField("Daily Time (HH:mm)", text: $viewModel.config.schedule.dailyTime)
            Toggle("Enable Sparse File Handling", isOn: $viewModel.config.repo.enableSparseHandling)
            Text("Uses borg --sparse with fixed chunking for safer sparse-file restores. Can reduce dedup efficiency for shifted files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Enable Wake Scheduling", isOn: $viewModel.config.schedule.wakeEnabled)
            Toggle("Use Privileged Snapshot Commands", isOn: $viewModel.config.preferences.usePrivilegedSnapshotCommands)
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repository Passphrase")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Stored in macOS Keychain for repo id \(viewModel.config.repo.id).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("Passphrase", text: $passphrase)
                    Button("Save Passphrase") {
                        Task {
                            let saved = await viewModel.savePassphrase(passphrase)
                            if saved {
                                passphrase = ""
                            }
                        }
                    }
                    .disabled(viewModel.config.repo.id.isEmpty || passphrase.isEmpty)
                }
                Text(viewModel.passphraseStored ? "Passphrase saved." : "No passphrase stored yet.")
                    .font(.caption)
                    .foregroundStyle(viewModel.passphraseStored ? .green : .secondary)
            }

            Divider()

            HStack {
                Text(helperStatusText)
                    .font(.caption)
                    .foregroundStyle(helperStatusColor)
                Spacer()
                Button("Install Helper") {
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
                .disabled(viewModel.installingHelper)
            }
            if viewModel.installingHelper {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing helper...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.fullDiskAccessGranted ? "Full Disk Access granted" : "Full Disk Access not granted")
                    .font(.caption)
                    .foregroundStyle(viewModel.fullDiskAccessGranted ? .green : .orange)
                Spacer()
                Button("Open Full Disk Access") {
                    viewModel.openFullDiskAccessSettings()
                }
                Button("Re-check") {
                    Task {
                        await viewModel.recheckFullDiskAccess(orchestrator: orchestrator)
                    }
                }
            }
            if !viewModel.fullDiskAccessGranted {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.fullDiskAccessDiagnosticLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var helperStatusText: String {
        switch viewModel.helperHealth {
        case .healthy:
            return "Privileged helper installed"
        case .notInstalled:
            return "Privileged helper not installed"
        case .unhealthy(let detail):
            return detail
        }
    }

    private var helperStatusColor: Color {
        switch viewModel.helperHealth {
        case .healthy:
            return .green
        case .notInstalled:
            return .secondary
        case .unhealthy:
            return .orange
        }
    }

    @ViewBuilder
    private func exclusionList(
        title: String,
        subtitle: String,
        items: Binding<[String]>,
        newValue: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, subtitle: subtitle)

            if items.wrappedValue.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(items.wrappedValue.indices), id: \.self) { index in
                            HStack {
                                TextField(
                                    placeholder,
                                    text: Binding(
                                        get: { items.wrappedValue[index] },
                                        set: { items.wrappedValue[index] = $0 }
                                    )
                                )
                                Button {
                                    items.wrappedValue.remove(at: index)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.red)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }

            HStack {
                TextField(placeholder, text: newValue)
                Button {
                    let value = newValue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    items.wrappedValue.append(value)
                    newValue.wrappedValue = ""
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func readOnlyList(
        title: String,
        subtitle: String,
        items: [String],
        maxHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, subtitle: subtitle)

            if items.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(items, id: \.self) { item in
                            Text(item)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: maxHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
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
}
