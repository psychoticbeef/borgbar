import Foundation

public enum BackupTrigger: String, Sendable {
    case manual
    case scheduled
    case retryAfterFailure
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
    private var lastArchiveSampleAt: Date?
    private var lastOriginalBytes: Int64?
    private var lastDeduplicatedBytes: Int64?

    private let configStore: ConfigStore
    private let keychain: KeychainService
    private let snapshotService: SnapshotService
    private let borg: BorgService
    private let historyStore: HistoryStore
    private let notifications: NotificationService
    private let wakeScheduler: WakeSchedulerService

    private var activeTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryScheduledAt: Date?

    public init(
        configStore: ConfigStore = ConfigStore(),
        keychain: KeychainService = KeychainService(),
        snapshotService: SnapshotService = LocalSnapshotService(),
        borg: BorgService = BorgService(),
        historyStore: HistoryStore = HistoryStore(),
        notifications: NotificationService = NotificationService(),
        wakeScheduler: WakeSchedulerService = WakeSchedulerService()
    ) {
        self.configStore = configStore
        self.keychain = keychain
        self.snapshotService = snapshotService
        self.borg = borg
        self.historyStore = historyStore
        self.notifications = notifications
        self.wakeScheduler = wakeScheduler
    }

    public func loadHistory() async {
        if let records = try? await historyStore.load() {
            lastRecord = records.first
            lastSuccessfulRecord = records.first(where: { $0.outcome == .success || $0.outcome == .successWithWarning })
        }
    }

    public func startManualRun() {
        startRun(trigger: .manual)
    }

    public func startScheduledRun() {
        startRun(trigger: .scheduled)
    }

    public func cancelRun() {
        guard isRunning else { return }
        borg.terminateActiveProcess()
        activeTask?.cancel()
        phase = .cancelled
        statusMessage = "Cancelling..."
    }

    public func cleanupRepositoryLockForTermination() async {
        guard !isRunning else { return }
        guard let config = try? await configStore.load() else { return }
        let passCommand = await keychain.passCommand(repoID: config.repo.id)
        do {
            try await borg.breakLock(config: config, passCommand: passCommand, timeoutSeconds: 20)
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
        let sleepAssertion = SleepAssertionService()
        sleepAssertion.begin(reason: "BorgBar backup in progress")
        archiveStats = nil
        lastArchiveSampleAt = nil
        lastOriginalBytes = nil
        lastDeduplicatedBytes = nil
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
            sleepAssertion.end()
            isRunning = false
        }

        do {
            update(.preflight, "Validating backup configuration")
            let config = try await configStore.load()
            loadedConfig = config
            try await configStore.validate(config)
            try await runPreflightWithRetry(config: config)

            update(.creatingSnapshot, "Creating APFS snapshot")
            let snapshot = try await snapshotService.createSnapshot(dailyTime: config.schedule.dailyTime)
            activeSnapshot = snapshot

            update(.mountingSnapshot, "Mounting snapshot read-only")
            try await snapshotService.mountSnapshot(snapshot)

            update(.creatingArchive, "Creating archive")
            let passCommand = await keychain.passCommand(repoID: config.repo.id)
            let progressHandler: @Sendable (String) -> Void = { [weak self] line in
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
            let backupStartedAt = Date()
            do {
                createOutput = try await borg.createArchive(
                    config: config,
                    snapshotMount: snapshot.mountPoint,
                    passCommand: passCommand,
                    onProgressLine: progressHandler
                )
            } catch {
                if error.localizedDescription.localizedCaseInsensitiveContains("lock") {
                    update(.creatingArchive, "Repository locked, attempting break-lock recovery")
                    try await borg.breakLock(config: config, passCommand: passCommand)
                    createOutput = try await borg.createArchive(
                        config: config,
                        snapshotMount: snapshot.mountPoint,
                        passCommand: passCommand,
                        onProgressLine: progressHandler
                    )
                } else {
                    throw error
                }
            }
            backupDuration = Date().timeIntervalSince(backupStartedAt)
            createSucceeded = true

            let pruneStartedAt = Date()
            do {
                update(.pruning, "Applying retention")
                _ = try await borg.prune(config: config, passCommand: passCommand)
            } catch {
                warningMessage = "Prune failed: \(error.localizedDescription)"
            }
            pruneDuration = Date().timeIntervalSince(pruneStartedAt)

            let compactStartedAt = Date()
            do {
                update(.compacting, "Compacting repository")
                _ = try await borg.compact(config: config, passCommand: passCommand)
            } catch {
                let compactMessage = "Compact failed: \(error.localizedDescription)"
                warningMessage = warningMessage.map { $0 + " | " + compactMessage } ?? compactMessage
            }
            compactDuration = Date().timeIntervalSince(compactStartedAt)

            do {
                repositoryStoredBytes = try await borg.repositorySizeBytes(config: config, passCommand: passCommand)
            } catch {
                let infoMessage = "Repository size unavailable: \(error.localizedDescription)"
                warningMessage = warningMessage.map { $0 + " | " + infoMessage } ?? infoMessage
            }

            update(.cleanup, "Cleaning up snapshot")
            if let snapshot = activeSnapshot {
                await snapshotService.deleteSnapshot(snapshot, deleteLocalSnapshot: true)
            }

            let end = Date()
            let archiveSummary = createOutput.map { BorgStatsParser.parseArchiveSummary(from: $0) }
            let metrics = BackupRunMetrics(
                readFromSourceBytes: archiveSummary?.thisArchiveOriginalBytes,
                writtenToRepoBytes: archiveSummary?.thisArchiveDeduplicatedBytes,
                repositoryStoredBytes: repositoryStoredBytes,
                backupDurationSeconds: backupDuration,
                pruneDurationSeconds: pruneDuration,
                compactDurationSeconds: compactDuration,
                totalDurationSeconds: end.timeIntervalSince(start)
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
                    await snapshotService.deleteSnapshot(snapshot, deleteLocalSnapshot: false)
                }
                let metrics = failedRunMetrics(start: start, end: end, backupDuration: backupDuration, pruneDuration: pruneDuration, compactDuration: compactDuration)
                try? await persist(
                    start: start,
                    end: end,
                    outcome: .cancelled,
                    failedPhase: phase,
                    summary: "Backup cancelled",
                    metrics: metrics
                )
                if let config = try? await configStore.load() {
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
                await snapshotService.deleteSnapshot(snapshot, deleteLocalSnapshot: false)
            }
            let end = Date()
            let failedPhase = createSucceeded ? BackupPhase.cleanup : phase
            let metrics = failedRunMetrics(start: start, end: end, backupDuration: backupDuration, pruneDuration: pruneDuration, compactDuration: compactDuration)
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
                configForFollowup = try? await configStore.load()
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
        try await historyStore.append(record)
        lastRecord = record
        if outcome == .success || outcome == .successWithWarning {
            lastSuccessfulRecord = record
        }
    }

    private func runPreflightWithRetry(config: AppConfig) async throws {
        try await PreflightService.run(config: config, keychain: keychain) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.update(.preflight, status)
            }
        }
    }

    private func scheduleFailureRetry(trigger: BackupTrigger, config: AppConfig?) {
        retryTask?.cancel()
        retryTask = nil
        retryScheduledAt = nil

        guard let config else {
            AppLogger.info("Backup failed (\(trigger.rawValue)); retry not scheduled because config is unavailable")
            return
        }

        guard let nextScheduledRun = DailySchedule.nextRunDate(from: config.schedule.dailyTime, referenceDate: Date()) else {
            AppLogger.info("Backup failed (\(trigger.rawValue)); retry not scheduled due to invalid schedule time \(config.schedule.dailyTime)")
            return
        }

        let retryDelay: TimeInterval = 60 * 60
        let deadline = Date().addingTimeInterval(retryDelay)

        guard deadline < nextScheduledRun else {
            let cutoffText = nextScheduledRun.formatted(date: .abbreviated, time: .shortened)
            AppLogger.info("Backup failed (\(trigger.rawValue)); retry window closes at \(cutoffText), no delayed retry scheduled")
            return
        }

        retryScheduledAt = deadline
        let timestamp = deadline.formatted(date: .abbreviated, time: .shortened)
        let cutoffText = nextScheduledRun.formatted(date: .abbreviated, time: .shortened)
        AppLogger.info("Backup failed (\(trigger.rawValue)); scheduling retry for \(timestamp) (retry window closes at \(cutoffText))")

        retryTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            } catch {
                return
            }

            while self.isRunning {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    return
                }
            }

            await MainActor.run {
                guard self.retryScheduledAt != nil else { return }
                if Date() >= nextScheduledRun {
                    self.retryTask = nil
                    self.retryScheduledAt = nil
                    let cutoffText = nextScheduledRun.formatted(date: .abbreviated, time: .shortened)
                    AppLogger.info("Failure retry window ended at \(cutoffText); waiting for scheduled backup")
                    return
                }
                self.retryTask = nil
                self.retryScheduledAt = nil
                self.startRun(trigger: .retryAfterFailure)
            }
        }
    }

    private func clearFailureRetry(reason: String) {
        guard retryTask != nil || retryScheduledAt != nil else { return }
        retryTask?.cancel()
        retryTask = nil
        retryScheduledAt = nil
        AppLogger.info("Cleared scheduled failure retry: \(reason)")
    }

    private func refreshWakeSchedule(using config: AppConfig) async {
        await wakeScheduler.updateWakeSchedule(
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
            await notifications.notify(title: title, body: body)
        case .all:
            await notifications.notify(title: title, body: body)
        }
    }

    private func applyProgressLine(_ line: String, now: Date) {
        if let checkpointStatus = BorgProgressParser.cacheCheckpointStatus(from: line) {
            refreshArchiveStatsLatestLine(line)
            update(.creatingArchive, checkpointStatus)
            return
        }

        if let parsed = BorgProgressParser.parseArchiveMetrics(line) {
            let readRate = BorgProgressParser.rate(
                currentBytes: parsed.originalBytes,
                previousBytes: lastOriginalBytes,
                currentTime: now,
                previousTime: lastArchiveSampleAt
            )
            let writeRate = BorgProgressParser.rate(
                currentBytes: parsed.deduplicatedBytes,
                previousBytes: lastDeduplicatedBytes,
                currentTime: now,
                previousTime: lastArchiveSampleAt
            )
            lastArchiveSampleAt = now
            lastOriginalBytes = parsed.originalBytes
            lastDeduplicatedBytes = parsed.deduplicatedBytes
            archiveStats = ArchiveLiveStats(
                originalBytes: parsed.originalBytes,
                compressedBytes: parsed.compressedBytes,
                deduplicatedBytes: parsed.deduplicatedBytes,
                fileCount: parsed.fileCount,
                readRateBytesPerSecond: readRate,
                writeRateBytesPerSecond: writeRate,
                throughputText: BorgProgressParser.parseThroughput(line),
                etaText: BorgProgressParser.parseETA(line),
                latestLine: line
            )
            let summary = "Creating archive: \(BorgProgressParser.humanBytes(parsed.originalBytes)) read, \(BorgProgressParser.humanBytes(parsed.deduplicatedBytes)) written"
            update(.creatingArchive, summary)
            return
        }

        if line.contains("B/s") || line.contains("ETA") || line.localizedCaseInsensitiveContains("files") {
            refreshArchiveStatsLatestLine(
                line,
                throughputText: BorgProgressParser.parseThroughput(line),
                etaText: BorgProgressParser.parseETA(line)
            )
            update(.creatingArchive, "Creating archive: \(line)")
        }
    }

    private func failedRunMetrics(
        start: Date,
        end: Date,
        backupDuration: TimeInterval?,
        pruneDuration: TimeInterval?,
        compactDuration: TimeInterval?
    ) -> BackupRunMetrics {
        BackupRunMetrics(
            readFromSourceBytes: nil,
            writtenToRepoBytes: nil,
            repositoryStoredBytes: nil,
            backupDurationSeconds: backupDuration,
            pruneDurationSeconds: pruneDuration,
            compactDurationSeconds: compactDuration,
            totalDurationSeconds: end.timeIntervalSince(start)
        )
    }

    private func refreshArchiveStatsLatestLine(
        _ line: String,
        throughputText: String? = nil,
        etaText: String? = nil
    ) {
        guard let stats = archiveStats else { return }
        archiveStats = ArchiveLiveStats(
            originalBytes: stats.originalBytes,
            compressedBytes: stats.compressedBytes,
            deduplicatedBytes: stats.deduplicatedBytes,
            fileCount: stats.fileCount,
            readRateBytesPerSecond: stats.readRateBytesPerSecond,
            writeRateBytesPerSecond: stats.writeRateBytesPerSecond,
            throughputText: throughputText ?? stats.throughputText,
            etaText: etaText ?? stats.etaText,
            latestLine: line
        )
    }
}
