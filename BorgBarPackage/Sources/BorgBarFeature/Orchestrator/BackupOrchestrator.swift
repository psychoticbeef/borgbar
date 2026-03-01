import Foundation

public enum BackupTrigger: String, Sendable {
    case manual
    case scheduled
    case retryAfterFailure
}

private struct ArchiveMaintenanceResult {
    let createOutput: String
    let warningMessage: String?
    let backupDuration: TimeInterval
    let pruneDuration: TimeInterval
    let compactDuration: TimeInterval
    let repositoryStoredBytes: Int64?
}

@MainActor
public final class BackupOrchestrator: ObservableObject {
    @Published public private(set) var phase: BackupPhase = .idle
    @Published public private(set) var statusMessage: String = "Idle"
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastRecord: BackupRunRecord?
    @Published public private(set) var lastSuccessfulRecord: BackupRunRecord?
    @Published public private(set) var archiveStats: ArchiveLiveStats?
    private var lastProgressAt: Date = .distantPast
    private var lastArchiveProgressLogAt: Date = .distantPast
    private var archiveProgressState = ArchiveProgressProcessorState()

    private let integration: BackupOrchestratorIntegrationPort
    private let failureRetryController = BackupFailureRetryController()

    private var activeTask: Task<Void, Never>?

    public init(
        configStore: ConfigStore = ConfigStore(),
        keychain: KeychainService = KeychainService(),
        snapshotService: SnapshotService = LocalSnapshotService(),
        borg: BorgService = BorgService(),
        historyStore: HistoryStore = HistoryStore(),
        notifications: NotificationService = NotificationService(),
        wakeScheduler: WakeSchedulerService = WakeSchedulerService(),
        sleepAssertion: SleepAssertionService = SleepAssertionService()
    ) {
        let dependencies = BackupOrchestratorDependencies(
            configStore: configStore,
            keychain: keychain,
            snapshotService: snapshotService,
            borg: borg,
            historyStore: historyStore,
            notifications: notifications,
            wakeScheduler: wakeScheduler,
            sleepAssertion: sleepAssertion
        )
        self.integration = DefaultBackupOrchestratorIntegrationPort(dependencies: dependencies)
    }

    init(integration: BackupOrchestratorIntegrationPort) {
        self.integration = integration
    }

    public func loadHistory() async {
        let records = await integration.loadHistory()
        lastRecord = records.first
        lastSuccessfulRecord = records.first(where: { $0.outcome == .success || $0.outcome == .successWithWarning })
    }

    public func startManualRun() {
        startRun(trigger: .manual)
    }

    public func startScheduledRun() {
        startRun(trigger: .scheduled)
    }

    public func cancelRun() {
        guard isRunning else { return }
        integration.terminateActiveProcess()
        activeTask?.cancel()
        phase = .cancelled
        statusMessage = "Cancelling..."
    }

    public func cleanupRepositoryLockForTermination() async {
        guard !isRunning else { return }
        guard let config = try? await integration.loadConfig() else { return }
        let passCommand = await integration.passCommand(repoID: config.repo.id)
        do {
            try await integration.breakLock(config: config, passCommand: passCommand, timeoutSeconds: 20)
            AppLogger.info("Termination cleanup: break-lock completed")
        } catch {
            // No lock is common; avoid surfacing this as a hard error during quit.
            AppLogger.info("Termination cleanup: break-lock skipped (\(error.localizedDescription))")
        }
    }

    public func setIdleStatus(_ message: String) {
        guard !isRunning else { return }
        phase = .idle
        statusMessage = message
        archiveStats = nil
        AppLogger.info("[idle] \(message)")
    }

    private func startRun(trigger: BackupTrigger) {
        guard !isRunning else { return }
        clearFailureRetry(reason: "Starting \(trigger.rawValue) run")
        activeTask = Task { [weak self] in
            await self?.runBackup(trigger: trigger)
        }
    }

    private func update(_ phase: BackupPhase, _ message: String) {
        self.phase = phase
        self.statusMessage = message
        let line = "[\(phase.rawValue)] \(message)"

        switch phase {
        case .creatingArchive:
            if message == "Creating archive" {
                AppLogger.info(line)
                lastArchiveProgressLogAt = Date()
                return
            }
            let now = Date()
            guard now.timeIntervalSince(lastArchiveProgressLogAt) >= 60 else { return }
            lastArchiveProgressLogAt = now
            AppLogger.debug(line)
        case .preflight:
            if message == "Validating backup configuration" {
                AppLogger.info(line)
            } else {
                AppLogger.debug(line)
            }
        default:
            AppLogger.info(line)
        }
    }

    private func runBackup(trigger: BackupTrigger) async {
        isRunning = true
        integration.beginSleepAssertion(reason: "BorgBar backup in progress")
        archiveStats = nil
        archiveProgressState = ArchiveProgressProcessorState()
        lastArchiveProgressLogAt = .distantPast
        let start = Date()
        var activeSnapshot: SnapshotRef?
        var loadedConfig: AppConfig?
        var createSucceeded = false
        var warningMessage: String?
        var createOutput: String?
        var backupDuration: TimeInterval?
        var pruneDuration: TimeInterval?
        var compactDuration: TimeInterval?
        var repositoryStoredBytes: Int64?

        defer {
            integration.endSleepAssertion()
            isRunning = false
        }

        do {
            update(.preflight, "Validating backup configuration")
            let config = try await integration.loadConfig()
            loadedConfig = config
            try await integration.validateConfig(config)
            try await runPreflightWithRetry(config: config)

            update(.creatingSnapshot, "Creating APFS snapshot")
            let snapshot = try await integration.createSnapshot(dailyTime: config.schedule.dailyTime)
            activeSnapshot = snapshot

            update(.mountingSnapshot, "Mounting snapshot read-only")
            try await integration.mountSnapshot(snapshot)

            let passCommand = await integration.passCommand(repoID: config.repo.id)
            let maintenanceResult = try await runArchiveAndMaintenance(
                config: config,
                snapshot: snapshot,
                passCommand: passCommand
            )
            createOutput = maintenanceResult.createOutput
            createSucceeded = true
            warningMessage = maintenanceResult.warningMessage
            backupDuration = maintenanceResult.backupDuration
            pruneDuration = maintenanceResult.pruneDuration
            compactDuration = maintenanceResult.compactDuration
            repositoryStoredBytes = maintenanceResult.repositoryStoredBytes

            let end = Date()
            let metrics = BackupRunMetricsFactory.completedRunMetrics(
                createOutput: createOutput,
                repositoryStoredBytes: repositoryStoredBytes,
                backupDuration: backupDuration,
                pruneDuration: pruneDuration,
                compactDuration: compactDuration,
                startedAt: start,
                finishedAt: end
            )
            if let warningMessage {
                update(.successWithWarning, warningMessage)
                archiveStats = nil
                clearFailureRetry(reason: "Backup completed with warning")
                try await persist(
                    start: start,
                    end: end,
                    outcome: .successWithWarning,
                    failedPhase: nil,
                    summary: warningMessage,
                    metrics: metrics
                )
                await notifyIfNeeded(
                    mode: config.preferences.notifications,
                    title: "BorgBar Backup Completed with Warning",
                    body: warningMessage,
                    isError: true
                )
                await refreshWakeSchedule(using: config)
            } else {
                update(.success, "Backup completed")
                archiveStats = nil
                clearFailureRetry(reason: "Backup completed successfully")
                try await persist(
                    start: start,
                    end: end,
                    outcome: .success,
                    failedPhase: nil,
                    summary: "Backup completed",
                    metrics: metrics
                )
                await notifyIfNeeded(
                    mode: config.preferences.notifications,
                    title: "BorgBar Backup Complete",
                    body: "Backup finished successfully.",
                    isError: false
                )
                await refreshWakeSchedule(using: config)
            }
        } catch {
            if Task.isCancelled {
                let end = Date()
                update(.cancelled, "Backup cancelled")
                archiveStats = nil
                clearFailureRetry(reason: "Backup cancelled")
                if let snapshot = activeSnapshot {
                    await integration.deleteSnapshot(snapshot, deleteLocalSnapshot: false)
                }
                let metrics = BackupRunMetricsFactory.failedRunMetrics(
                    startedAt: start,
                    finishedAt: end,
                    backupDuration: backupDuration,
                    pruneDuration: pruneDuration,
                    compactDuration: compactDuration
                )
                try? await persist(
                    start: start,
                    end: end,
                    outcome: .cancelled,
                    failedPhase: phase,
                    summary: "Backup cancelled",
                    metrics: metrics
                )
                if let config = try? await integration.loadConfig() {
                    await notifyIfNeeded(
                        mode: config.preferences.notifications,
                        title: "BorgBar Backup Cancelled",
                        body: "Backup was cancelled.",
                        isError: true
                    )
                    await refreshWakeSchedule(using: config)
                }
                return
            }

            update(.failed, error.localizedDescription)
            archiveStats = nil
            if let snapshot = activeSnapshot {
                await integration.deleteSnapshot(snapshot, deleteLocalSnapshot: false)
            }
            let end = Date()
            let failedPhase = createSucceeded ? BackupPhase.cleanup : phase
            let metrics = BackupRunMetricsFactory.failedRunMetrics(
                startedAt: start,
                finishedAt: end,
                backupDuration: backupDuration,
                pruneDuration: pruneDuration,
                compactDuration: compactDuration
            )
            try? await persist(
                start: start,
                end: end,
                outcome: .failed,
                failedPhase: failedPhase,
                summary: error.localizedDescription,
                metrics: metrics
            )
            let configForFollowup: AppConfig?
            if let loadedConfig {
                configForFollowup = loadedConfig
            } else {
                configForFollowup = try? await integration.loadConfig()
            }
            scheduleFailureRetry(trigger: trigger, config: configForFollowup)
            if let config = configForFollowup {
                await notifyIfNeeded(
                    mode: config.preferences.notifications,
                    title: "BorgBar Backup Failed",
                    body: error.localizedDescription,
                    isError: true
                )
                await refreshWakeSchedule(using: config)
            }
        }
    }

    private func persist(
        start: Date,
        end: Date,
        outcome: RunOutcome,
        failedPhase: BackupPhase?,
        summary: String,
        metrics: BackupRunMetrics?
    ) async throws {
        let record = BackupRunRecord(
            startedAt: start,
            finishedAt: end,
            outcome: outcome,
            failedPhase: failedPhase,
            summary: summary,
            metrics: metrics
        )
        try await integration.appendHistory(record)
        lastRecord = record
        if outcome == .success || outcome == .successWithWarning {
            lastSuccessfulRecord = record
        }
    }

    private func runPreflightWithRetry(config: AppConfig) async throws {
        try await integration.runPreflight(config: config) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.update(.preflight, status)
            }
        }
    }

    private func scheduleFailureRetry(trigger: BackupTrigger, config: AppConfig?) {
        guard let config else {
            AppLogger.info("Backup failed (\(trigger.rawValue)); retry not scheduled because config is unavailable")
            return
        }

        switch BackupFailureRetryPlanner.plan(now: Date(), dailyTime: config.schedule.dailyTime) {
        case .invalidSchedule:
            AppLogger.info("Backup failed (\(trigger.rawValue)); retry not scheduled due to invalid schedule time \(config.schedule.dailyTime)")
            return
        case .outsideWindow(let nextScheduledRun):
            let cutoffText = nextScheduledRun.formatted(date: .abbreviated, time: .shortened)
            AppLogger.info("Backup failed (\(trigger.rawValue)); retry window closes at \(cutoffText), no delayed retry scheduled")
            return
        case .scheduled(let plan):
            failureRetryController.schedule(
                plan: plan,
                trigger: trigger,
                isRunning: { self.isRunning },
                onRetry: { self.startRun(trigger: .retryAfterFailure) }
            )
        }
    }

    private func clearFailureRetry(reason: String) {
        failureRetryController.clear(reason: reason)
    }

    private func refreshWakeSchedule(using config: AppConfig) async {
        await integration.updateWakeSchedule(
            dailyTime: config.schedule.dailyTime,
            enabled: config.schedule.wakeEnabled
        )
    }

    private func notifyIfNeeded(mode: NotificationMode, title: String, body: String, isError: Bool) async {
        switch mode {
        case .none:
            return
        case .errorsOnly:
            guard isError else { return }
            await integration.notify(title: title, body: body)
        case .all:
            await integration.notify(title: title, body: body)
        }
    }

    private func runArchiveAndMaintenance(
        config: AppConfig,
        snapshot: SnapshotRef,
        passCommand: String
    ) async throws -> ArchiveMaintenanceResult {
        update(.creatingArchive, "Creating archive")
        let progressHandler = makeProgressHandler()
        let backupStartedAt = Date()
        let createOutput = try await createArchiveWithLockRecovery(
            config: config,
            snapshotMount: snapshot.mountPoint,
            passCommand: passCommand,
            progressHandler: progressHandler
        )
        let backupDuration = Date().timeIntervalSince(backupStartedAt)

        var warningMessage: String?

        let pruneStartedAt = Date()
        do {
            update(.pruning, "Applying retention")
            try await integration.prune(config: config, passCommand: passCommand)
        } catch {
            warningMessage = "Prune failed: \(error.localizedDescription)"
        }
        let pruneDuration = Date().timeIntervalSince(pruneStartedAt)

        let compactStartedAt = Date()
        do {
            update(.compacting, "Compacting repository")
            try await integration.compact(config: config, passCommand: passCommand)
        } catch {
            let compactMessage = "Compact failed: \(error.localizedDescription)"
            warningMessage = warningMessage.map { $0 + " | " + compactMessage } ?? compactMessage
        }
        let compactDuration = Date().timeIntervalSince(compactStartedAt)

        var repositoryStoredBytes: Int64?
        do {
            repositoryStoredBytes = try await integration.repositorySizeBytes(config: config, passCommand: passCommand)
        } catch {
            let infoMessage = "Repository size unavailable: \(error.localizedDescription)"
            warningMessage = warningMessage.map { $0 + " | " + infoMessage } ?? infoMessage
        }
        if let targetGiB = config.repo.maxRepositorySizeGiB,
           targetGiB > 0,
           let repositoryStoredBytes {
            let targetBytes = Int64(targetGiB) * 1_073_741_824
            if repositoryStoredBytes > targetBytes {
                do {
                    if let suggestion = try await integration.suggestTrimToTarget(
                        config: config,
                        passCommand: passCommand,
                        currentRepositoryBytes: repositoryStoredBytes,
                        targetRepositoryBytes: targetBytes
                    ) {
                        let message = formatTrimSuggestionWarning(suggestion)
                        warningMessage = warningMessage.map { $0 + " | " + message } ?? message
                        let shown = suggestion.archivesToDeleteOldestFirst.prefix(10).joined(separator: ", ")
                        let more = suggestion.archivesToDeleteOldestFirst.count > 10
                            ? " (+\(suggestion.archivesToDeleteOldestFirst.count - 10) more)"
                            : ""
                        AppLogger.info(
                            "Repository exceeds target \(BorgProgressParser.humanBytes(targetBytes)); " +
                            "suggested oldest deletions (estimated): \(shown)\(more)"
                        )
                    } else {
                        let message = "Repo exceeds target by \(BorgProgressParser.humanBytes(repositoryStoredBytes - targetBytes)); no trim suggestion available"
                        warningMessage = warningMessage.map { $0 + " | " + message } ?? message
                    }
                } catch {
                    let message = "Repo trim analysis unavailable: \(error.localizedDescription)"
                    warningMessage = warningMessage.map { $0 + " | " + message } ?? message
                }
            }
        }

        update(.cleanup, "Cleaning up snapshot")
        await integration.deleteSnapshot(snapshot, deleteLocalSnapshot: true)

        return ArchiveMaintenanceResult(
            createOutput: createOutput,
            warningMessage: warningMessage,
            backupDuration: backupDuration,
            pruneDuration: pruneDuration,
            compactDuration: compactDuration,
            repositoryStoredBytes: repositoryStoredBytes
        )
    }

    private func formatTrimSuggestionWarning(_ suggestion: RepositoryTrimSuggestion) -> String {
        let shown = suggestion.archivesToDeleteOldestFirst.prefix(3)
        let archiveText = shown.joined(separator: ", ")
        let remainingCount = suggestion.archivesToDeleteOldestFirst.count - shown.count
        let suffix = remainingCount > 0 ? " (+\(remainingCount) more)" : ""
        let stillAboveTarget = suggestion.projectedBytes > suggestion.targetBytes
            ? " Still above target after estimate."
            : ""
        let analysisLimitNote = suggestion.analyzedArchiveCount < suggestion.totalArchiveCount
            ? " (analyzed oldest \(suggestion.analyzedArchiveCount)/\(suggestion.totalArchiveCount) archives)"
            : ""
        return "Repo above target by \(BorgProgressParser.humanBytes(suggestion.excessBytes)). " +
            "Suggested oldest deletions (estimate): \(archiveText)\(suffix). " +
            "Projected size ~\(BorgProgressParser.humanBytes(suggestion.projectedBytes))." +
            stillAboveTarget + analysisLimitNote
    }

    private func createArchiveWithLockRecovery(
        config: AppConfig,
        snapshotMount: String,
        passCommand: String,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        do {
            return try await integration.createArchive(
                config: config,
                snapshotMount: snapshotMount,
                passCommand: passCommand,
                onProgressLine: progressHandler
            )
        } catch {
            guard error.localizedDescription.localizedCaseInsensitiveContains("lock") else {
                throw error
            }
            update(.creatingArchive, "Repository locked, attempting break-lock recovery")
            try await integration.breakLock(config: config, passCommand: passCommand, timeoutSeconds: nil)
            return try await integration.createArchive(
                config: config,
                snapshotMount: snapshotMount,
                passCommand: passCommand,
                onProgressLine: progressHandler
            )
        }
    }

    private func makeProgressHandler() -> (@Sendable (String) -> Void) {
        { [weak self] line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastProgressAt) >= 0.3 else { return }
                self.lastProgressAt = now
                self.applyProgressLine(trimmed, now: now)
            }
        }
    }

    private func applyProgressLine(_ line: String, now: Date) {
        guard let result = ArchiveProgressProcessor.process(
            line: line,
            now: now,
            currentStats: archiveStats,
            state: archiveProgressState
        ) else {
            return
        }

        archiveProgressState = result.state
        archiveStats = result.stats
        if let statusMessage = result.statusMessage {
            update(.creatingArchive, statusMessage)
        }
    }

}
