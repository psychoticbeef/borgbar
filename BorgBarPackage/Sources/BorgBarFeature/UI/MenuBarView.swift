import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject private var orchestrator: BackupOrchestrator
    private let onOpenSettingsWindow: () -> Void

    public init(
        orchestrator: BackupOrchestrator,
        openSettingsWindow: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    ) {
        self.orchestrator = orchestrator
        self.onOpenSettingsWindow = openSettingsWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BorgBar")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(orchestrator.statusMessage)
                        .font(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }

            if orchestrator.phase == .creatingArchive, let stats = orchestrator.archiveStats {
                GroupBox("Live Progress") {
                    VStack(alignment: .leading, spacing: 4) {
                        statRow("Read", value: bytes(stats.originalBytes))
                        statRow("Repo out", value: bytes(stats.deduplicatedBytes))
                        statRow("Compressed", value: bytes(stats.compressedBytes))
                        statRow("Files", value: number(stats.fileCount))
                        statRow("Read rate", value: bytesPerSecond(stats.readRateBytesPerSecond))
                        statRow("Write rate", value: bytesPerSecond(stats.writeRateBytesPerSecond))
                        if let throughput = stats.throughputText {
                            statRow("Borg speed", value: throughput)
                        }
                        if let eta = stats.etaText {
                            statRow("ETA", value: eta.replacingOccurrences(of: "ETA ", with: ""))
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }

            if let last = orchestrator.lastRecord {
                GroupBox("Last Run") {
                    VStack(alignment: .leading, spacing: 4) {
                        statRow("Outcome", value: last.outcome.rawValue.capitalized)
                        statRow("Finished", value: last.finishedAt.formatted(date: .omitted, time: .shortened))
                        Text(last.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }

            if let lastBackup = orchestrator.lastSuccessfulRecord {
                GroupBox("Last Backup") {
                    VStack(alignment: .leading, spacing: 4) {
                        statRow("Finished", value: lastBackup.finishedAt.formatted(date: .omitted, time: .shortened))
                        statRow("Read", value: bytes(lastBackup.metrics?.readFromSourceBytes))
                        statRow("Repo out", value: bytes(lastBackup.metrics?.writtenToRepoBytes))
                        statRow("Repo size", value: bytes(lastBackup.metrics?.repositoryStoredBytes))
                        statRow("Backup", value: duration(lastBackup.metrics?.backupDurationSeconds))
                        statRow("Prune", value: duration(lastBackup.metrics?.pruneDurationSeconds))
                        statRow("Compact", value: duration(lastBackup.metrics?.compactDurationSeconds))
                        statRow("Total", value: duration(lastBackup.metrics?.totalDurationSeconds))
                    }
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }

            HStack(spacing: 8) {
                Button("Back Up Now") {
                    orchestrator.startManualRun()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(orchestrator.isRunning)

                Button("Stop") {
                    orchestrator.cancelRun()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .frame(maxWidth: .infinity)
                .disabled(!orchestrator.isRunning)
            }

            HStack(spacing: 8) {
                utilityButton(title: "Settings", systemImage: "gearshape.fill", action: openSettingsWindow)
                utilityButton(title: "Logs", systemImage: "doc.text") {
                    let path = AppPaths().logsDirectory.path
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                utilityButton(title: "Quit", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private var title: String {
        switch orchestrator.phase {
        case .idle:
            return "BorgBar"
        case .success:
            return "Backup Complete"
        case .successWithWarning:
            return "Backup Complete (Warning)"
        case .failed:
            return "Backup Failed"
        case .cancelled:
            return "Backup Cancelled"
        default:
            return "Backing Up..."
        }
    }

    @ViewBuilder
    private func utilityButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 14)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            if orchestrator.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(orchestrator.isRunning ? "Running" : "Idle")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(orchestrator.isRunning ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.16))
        )
    }

    private func openSettingsWindow() {
        onOpenSettingsWindow()
    }

    private func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value else { return "n/a" }
        return bytes(value)
    }

    private func bytesPerSecond(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(bytes(Int64(value)))/s"
    }

    private func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "n/a" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}
