import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
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

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedSection == section ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 190, idealWidth: 220, maxWidth: 240)
    }
}

struct BackupScopeSettingsSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var newExcludedFolder: String
    @Binding var newExcludePattern: String
    @Binding var newExcludeIfPresentMarker: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditableStringListView(
                title: "User: Exclude Folder Contents",
                subtitle: "Keeps the folder, excludes children (example: ~/Downloads).",
                items: $viewModel.config.repo.userExcludeDirectoryContents,
                newValue: $newExcludedFolder,
                placeholder: "~/Downloads"
            )

            EditableStringListView(
                title: "User: Exclude Glob Patterns",
                subtitle: "Borg --exclude patterns (example: */venv/*).",
                items: $viewModel.config.repo.userExcludePatterns,
                newValue: $newExcludePattern,
                placeholder: "*/venv/*"
            )

            EditableStringListView(
                title: "User: Exclude If Present Markers",
                subtitle: "Exclude directories containing these marker files (borg --exclude-if-present).",
                items: $viewModel.config.repo.userExcludeIfPresentMarkers,
                newValue: $newExcludeIfPresentMarker,
                placeholder: ".nobackup"
            )

            ReadOnlyStringListView(
                title: "Common-Sense Exclusions",
                subtitle: "Built-in exclusions always applied.",
                items: viewModel.config.repo.commonSenseExcludePatterns,
                maxHeight: 150
            )

            ReadOnlyStringListView(
                title: "Time Machine Exclusions",
                subtitle: viewModel.timeMachineSubtitle,
                items: viewModel.config.repo.timeMachineExcludedPaths,
                maxHeight: 300
            )
        }
    }
}

struct RepositorySettingsSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Repo Name", text: $viewModel.config.repo.name)
            TextField("Repository Path", text: $viewModel.config.repo.path)
            TextField("SSH Key Path", text: $viewModel.config.repo.sshKeyPath)
            TextField("Daily Time (HH:mm)", text: $viewModel.config.schedule.dailyTime)
            TextField("Max Repo Size (GiB, optional)", text: maxRepoSizeGiBBinding)
                .textFieldStyle(.roundedBorder)
            Text("If set, BorgBar estimates oldest archives to delete when repo size exceeds this target.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Notifications", selection: $viewModel.config.preferences.notifications) {
                ForEach(NotificationMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Launch BorgBar at Login", isOn: $viewModel.config.preferences.launchAtLogin)
            Toggle("Enable Sparse File Handling", isOn: $viewModel.config.repo.enableSparseHandling)
            Text("Uses borg --sparse with fixed chunking for safer sparse-file restores. Can reduce dedup efficiency for shifted files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle("Enable Healthchecks.io Pings", isOn: $viewModel.config.preferences.healthchecksEnabled)
            TextField("Healthchecks Ping URL", text: $viewModel.config.preferences.healthchecksPingURL)
                .textFieldStyle(.roundedBorder)
                .disabled(!viewModel.config.preferences.healthchecksEnabled)
            Toggle("Ping Healthchecks on Start", isOn: $viewModel.config.preferences.healthchecksPingOnStart)
                .disabled(!viewModel.config.preferences.healthchecksEnabled)
            Toggle("Ping Healthchecks on Error", isOn: $viewModel.config.preferences.healthchecksPingOnError)
                .disabled(!viewModel.config.preferences.healthchecksEnabled)
            Text("Default behavior is success-only. Enable start and error pings only if you want extra signal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Enable Wake Scheduling", isOn: $viewModel.config.schedule.wakeEnabled)
            Toggle("Use Privileged Snapshot Commands", isOn: $viewModel.config.preferences.usePrivilegedSnapshotCommands)
        }
    }

    private var maxRepoSizeGiBBinding: Binding<String> {
        Binding(
            get: {
                guard let value = viewModel.config.repo.maxRepositorySizeGiB else { return "" }
                return String(value)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    viewModel.config.repo.maxRepositorySizeGiB = nil
                    return
                }
                if let parsed = Int(trimmed), parsed > 0 {
                    viewModel.config.repo.maxRepositorySizeGiB = parsed
                }
            }
        )
    }
}

struct PermissionsSettingsSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onOpenFullDiskAccess: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.fullDiskAccessGranted ? "Full Disk Access granted" : "Full Disk Access not granted")
                    .font(.caption)
                    .foregroundStyle(viewModel.fullDiskAccessGranted ? .green : .orange)
                Spacer()
                Button("Open Full Disk Access") {
                    onOpenFullDiskAccess()
                }
                Button("Re-check") {
                    onRecheck()
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
}

struct SecuritySettingsSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var passphrase: String
    let onSavePassphrase: () -> Void
    let onInstallHelper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeaderView(
                    title: "Repository Passphrase",
                    subtitle: "Stored for repo id \(viewModel.config.repo.id)."
                )
                Picker("Passphrase Storage", selection: $viewModel.config.preferences.passphraseStorage) {
                    ForEach(PassphraseStorageMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(viewModel.config.preferences.passphraseStorage.settingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let availabilityMessage = viewModel.passphraseStorageAvailabilityMessage,
                   viewModel.config.preferences.passphraseStorage == .iCloudKeychain {
                    Text(availabilityMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if viewModel.config.preferences.passphraseStorage == .iCloudKeychain {
                    Text("After switching storage location, save the passphrase again to copy it into iCloud Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    SecureField("Passphrase", text: $passphrase)
                    Button("Save Passphrase") {
                        onSavePassphrase()
                    }
                    .disabled(
                        viewModel.config.repo.id.isEmpty ||
                        passphrase.isEmpty ||
                        viewModel.passphraseStorageAvailabilityMessage != nil
                    )
                }
                Text(
                    viewModel.passphraseStored
                        ? "Passphrase saved in \(viewModel.config.preferences.passphraseStorage.keychainDisplayName)."
                        : "No passphrase stored in \(viewModel.config.preferences.passphraseStorage.keychainDisplayName) yet."
                )
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
                    onInstallHelper()
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
}

struct EditableStringListView: View {
    let title: String
    let subtitle: String
    @Binding var items: [String]
    @Binding var newValue: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeaderView(title: title, subtitle: subtitle)

            if items.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(items.indices), id: \.self) { index in
                            HStack {
                                TextField(
                                    placeholder,
                                    text: Binding(
                                        get: { items[index] },
                                        set: { items[index] = $0 }
                                    )
                                )
                                Button {
                                    items.remove(at: index)
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
                TextField(placeholder, text: $newValue)
                Button {
                    let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    items.append(value)
                    newValue = ""
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

struct ReadOnlyStringListView: View {
    let title: String
    let subtitle: String
    let items: [String]
    let maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeaderView(title: title, subtitle: subtitle)

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
}

struct SettingsSectionHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
