import Foundation
import Testing
@testable import BorgBarFeature

@Test func borgStatsParserHandlesArchiveSummaryAndRepositorySize() {
    let output = """
    This archive: 1.5 GiB 1.0 GiB 500 MiB
    All archives: 2.0 GiB 1.5 GiB 750 MiB
    Repository size: 12.5 GB
    """

    let summary = BorgStatsParser.parseArchiveSummary(from: output)
    #expect(summary.thisArchiveOriginalBytes == 1_610_612_736)
    #expect(summary.thisArchiveDeduplicatedBytes == 524_288_000)
    #expect(summary.allArchivesDeduplicatedBytes == 786_432_000)
    #expect(BorgStatsParser.parseRepositorySizeBytes(from: output) == 12_500_000_000)
}

@Test func borgStatsParserParsesRepositorySizeFromJSONAndFallbackText() {
    let json = """
    {
      "cache": {
        "stats": {
          "total_csize": 1503358425546,
          "unique_csize": 130889432424
        }
      }
    }
    """
    #expect(BorgStatsParser.parseRepositorySizeBytesFromJSON(json) == 130_889_432_424)

    let textWithoutRepositorySize = """
                           Original size      Compressed size    Deduplicated size
    All archives:                2.46 TB              1.50 TB            130.89 GB
    """
    #expect(BorgStatsParser.parseRepositorySizeBytes(from: textWithoutRepositorySize) == 130_890_000_000)
}

@Test func borgStatsParserHandlesHumanBytesVariants() {
    #expect(BorgStatsParser.parseHumanBytes(nil) == nil)
    #expect(BorgStatsParser.parseHumanBytes("") == nil)
    #expect(BorgStatsParser.parseHumanBytes("Zero B") == 0)
    #expect(BorgStatsParser.parseHumanBytes("1 KB") == 1_000)
    #expect(BorgStatsParser.parseHumanBytes("1 KiB") == 1_024)
    #expect(BorgStatsParser.parseHumanBytes("1,5 MiB") == 1_572_864)
    #expect(BorgStatsParser.parseHumanBytes("1,234.5 MB") == 1_234_500_000)
    #expect(BorgStatsParser.parseHumanBytes("not-a-size") == nil)
    #expect(BorgStatsParser.parseHumanBytes("10 XB") == nil)
}

@Test func borgStatsParserCoversAllUnitMultipliers() {
    #expect(BorgStatsParser.parseHumanBytes("2 B") == 2)
    #expect(BorgStatsParser.parseHumanBytes("2 KB") == 2_000)
    #expect(BorgStatsParser.parseHumanBytes("2 MB") == 2_000_000)
    #expect(BorgStatsParser.parseHumanBytes("2 GB") == 2_000_000_000)
    #expect(BorgStatsParser.parseHumanBytes("2 TB") == 2_000_000_000_000)
    #expect(BorgStatsParser.parseHumanBytes("2 PB") == 2_000_000_000_000_000)
    #expect(BorgStatsParser.parseHumanBytes("2 KiB") == 2_048)
    #expect(BorgStatsParser.parseHumanBytes("2 MiB") == 2_097_152)
    #expect(BorgStatsParser.parseHumanBytes("2 GiB") == 2_147_483_648)
    #expect(BorgStatsParser.parseHumanBytes("2 TiB") == 2_199_023_255_552)
    #expect(BorgStatsParser.parseHumanBytes("2 PiB") == 2_251_799_813_685_248)
    #expect(BorgStatsParser.parseHumanBytes("2 gib") == 2_147_483_648)
}

@Test func borgStatsParserHandlesMissingRows() {
    let output = "This archive: invalid"
    let summary = BorgStatsParser.parseArchiveSummary(from: output)
    #expect(summary.thisArchiveOriginalBytes == nil)
    #expect(summary.thisArchiveDeduplicatedBytes == nil)
    #expect(summary.allArchivesDeduplicatedBytes == nil)
    #expect(BorgStatsParser.parseRepositorySizeBytes(from: output) == nil)
}

@Test func borgCreateCommandBuilderBuildsSparseAndExclusions() {
    var config = AppConfig.default
    config.repo.enableSparseHandling = true
    config.repo.compression = "zstd,8"
    config.repo.includePaths = ["~", "/Volumes/Media"]
    config.repo.commonSenseExcludePatterns = ["*/Caches/*", "*/node_modules/*"]
    config.repo.userExcludePatterns = ["*/tmp/*", "*/node_modules/*"]
    config.repo.userExcludeIfPresentMarkers = [" .nobackup ", ".gitignore", "", ".nobackup"]
    config.repo.userExcludeDirectoryContents = ["~/Downloads", "/tmp/scratch"]
    config.repo.timeMachineExcludedPaths = ["/Users/da/Library/Caches", "/Users/da/Library/Logs"]

    let args = BorgCreateCommandBuilder.buildArguments(
        config: config,
        snapshotMount: "/tmp/snap",
        archiveName: "archive-1"
    )

    #expect(args.prefix(4) == ["create", "--progress", "--stats", "::archive-1"])
    #expect(args.contains("--sparse"))
    #expect(args.contains("--chunker-params"))
    #expect(args.contains("fixed,1048576"))

    #expect(args.contains("--compression"))
    #expect(args.contains("zstd,8"))
    #expect(args.contains(where: { $0 == "--exclude-if-present" }))
    #expect(args.contains(".nobackup"))
    #expect(args.contains(".gitignore"))

    let home = NSString(string: "~").expandingTildeInPath
    let downloads = "\(home)/Downloads"
    #expect(args.contains("/tmp/snap\(downloads)/*"))
    #expect(args.contains("/tmp/snap\(downloads)/.[!.]*"))
    #expect(args.contains("/tmp/snap\(downloads)/..?*"))
    #expect(args.contains("/tmp/snap/tmp/scratch/*"))
    #expect(args.contains("/tmp/snap/tmp/scratch/.[!.]*"))
    #expect(args.contains("/tmp/snap/tmp/scratch/..?*"))

    // Caches should be skipped because it is already covered by defaults; Logs should be added.
    #expect(!args.contains("/tmp/snap/Users/da/Library/Caches"))
    #expect(args.contains("/tmp/snap/Users/da/Library/Logs"))

    #expect(args.suffix(2) == ["/tmp/snap\(home)", "/tmp/snap/Volumes/Media"])
}

@Test func borgCreateCommandBuilderOmitsSparseWhenDisabled() {
    var config = AppConfig.default
    config.repo.enableSparseHandling = false

    let args = BorgCreateCommandBuilder.buildArguments(
        config: config,
        snapshotMount: "/tmp/snap",
        archiveName: "archive-2"
    )

    #expect(!args.contains("--sparse"))
    #expect(!args.contains("fixed,1048576"))
}

@Test func dailyScheduleComputesNextRunForFutureAndPast() {
    let calendar = fixedCalendar()
    let morning = makeDate(year: 2026, month: 3, day: 1, hour: 8, minute: 0, calendar: calendar)
    let evening = makeDate(year: 2026, month: 3, day: 1, hour: 18, minute: 0, calendar: calendar)

    let future = DailySchedule.nextRunDate(from: "09:30", referenceDate: morning, calendar: calendar)
    #expect(future == makeDate(year: 2026, month: 3, day: 1, hour: 9, minute: 30, calendar: calendar))

    let nextDay = DailySchedule.nextRunDate(from: "09:30", referenceDate: evening, calendar: calendar)
    #expect(nextDay == makeDate(year: 2026, month: 3, day: 2, hour: 9, minute: 30, calendar: calendar))

    #expect(DailySchedule.nextRunDate(from: "not-a-time", referenceDate: morning, calendar: calendar) == nil)
}

@Test func backupScheduleEvaluatorCoversDecisionBranches() {
    let evaluator = BackupScheduleEvaluator()
    let calendar = fixedCalendar()
    let day = makeDate(year: 2026, month: 3, day: 1, hour: 10, minute: 0, calendar: calendar)
    let dayKey = "2026-3-1"

    let invalid = evaluator.evaluate(
        dailyTime: "3pm",
        now: day,
        lastTriggeredDay: nil,
        hasCompletedRunToday: false,
        calendar: calendar
    )
    #expect(!invalid.shouldTrigger)
    #expect(invalid.updatedLastTriggeredDay == nil)

    let alreadyTriggered = evaluator.evaluate(
        dailyTime: "09:00",
        now: day,
        lastTriggeredDay: dayKey,
        hasCompletedRunToday: false,
        calendar: calendar
    )
    #expect(!alreadyTriggered.shouldTrigger)
    #expect(alreadyTriggered.updatedLastTriggeredDay == dayKey)

    let beforeRunTime = evaluator.evaluate(
        dailyTime: "11:00",
        now: day,
        lastTriggeredDay: nil,
        hasCompletedRunToday: false,
        calendar: calendar
    )
    #expect(!beforeRunTime.shouldTrigger)
    #expect(beforeRunTime.updatedLastTriggeredDay == nil)

    let completedToday = evaluator.evaluate(
        dailyTime: "09:00",
        now: day,
        lastTriggeredDay: nil,
        hasCompletedRunToday: true,
        calendar: calendar
    )
    #expect(!completedToday.shouldTrigger)
    #expect(completedToday.updatedLastTriggeredDay == dayKey)

    let trigger = evaluator.evaluate(
        dailyTime: "09:00",
        now: day,
        lastTriggeredDay: nil,
        hasCompletedRunToday: false,
        calendar: calendar
    )
    #expect(trigger.shouldTrigger)
    #expect(trigger.updatedLastTriggeredDay == dayKey)
}

@Test func backupFailureRetryPlannerCoversOutcomes() {
    let calendar = Calendar.current
    let now = Date()
    let localNow = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
    let nowHour = localNow.hour ?? 0
    let nowMinute = localNow.minute ?? 0
    let minutePlusOne = (nowMinute + 1) % 60
    let hourForSoonRun = (nowMinute == 59) ? (nowHour + 1) % 24 : nowHour
    let hourForLaterRun = (nowHour + 3) % 24

    let soonRun = String(format: "%02d:%02d", hourForSoonRun, minutePlusOne)
    let laterRun = String(format: "%02d:%02d", hourForLaterRun, nowMinute)

    let invalid = BackupFailureRetryPlanner.plan(now: now, dailyTime: "x", retryDelay: 10)
    switch invalid {
    case .invalidSchedule:
        break
    default:
        Issue.record("Expected invalid schedule")
    }

    let outside = BackupFailureRetryPlanner.plan(now: now, dailyTime: soonRun, retryDelay: 60 * 60)
    switch outside {
    case .outsideWindow(let next):
        #expect(next > now)
        #expect(next.timeIntervalSince(now) <= 3600)
    default:
        Issue.record("Expected outside-window result")
    }

    let scheduled = BackupFailureRetryPlanner.plan(now: now, dailyTime: laterRun, retryDelay: 60 * 60)
    switch scheduled {
    case .scheduled(let plan):
        #expect(plan.retryAt.timeIntervalSince(now) >= 3599)
        #expect(plan.retryAt.timeIntervalSince(now) <= 3601)
        #expect(plan.cutoffAt > plan.retryAt)
    default:
        Issue.record("Expected scheduled result")
    }
}

@Test func wakeSchedulePlannerParsesAndDetectsLegacyOutput() {
    let planner = WakeSchedulePlanner()
    #expect(planner.parseTime(from: "03:15")?.hour == 3)
    #expect(planner.parseTime(from: "03:15")?.minute == 15)
    #expect(planner.parseTime(from: "24:00") == nil)
    #expect(planner.parseTime(from: "03:99") == nil)
    #expect(planner.parseTime(from: "oops") == nil)

    let output = """
    wake or power on at 3:00AM every day
    another line
    """
    #expect(planner.hasLegacyDailyWakeRepeat(output, hour: 3, minute: 0))
    #expect(!planner.hasLegacyDailyWakeRepeat(output, hour: 4, minute: 0))
}

@Test func wakeSchedulePlannerFormatsAndComputesWakeDate() {
    let planner = WakeSchedulePlanner()
    let calendar = fixedCalendar()
    let reference = makeDate(year: 2026, month: 3, day: 1, hour: 2, minute: 0, calendar: calendar)

    let next = planner.nextWakeDate(hour: 3, minute: 0, referenceDate: reference)
    let expected = DailySchedule.nextRunDate(from: "03:00", referenceDate: reference)
    #expect(next == expected)

    let formatted = planner.formatPMSetDate(reference)
    #expect(formatted.range(of: #"^\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil)
}

@Test func wakeScheduleUpdatePolicyCoversOutcomes() {
    let planner = WakeSchedulePlanner()
    let calendar = fixedCalendar()
    let reference = makeDate(year: 2026, month: 3, day: 1, hour: 1, minute: 0, calendar: calendar)
    let legacyOutput = "wake at 3:00AM every day"

    let disabled = WakeScheduleUpdatePolicy.evaluate(
        hour: 3,
        minute: 0,
        enabled: false,
        currentScheduleOutput: legacyOutput,
        planner: planner,
        referenceDate: reference
    )
    switch disabled {
    case .disabled(let removeLegacyRepeat):
        #expect(removeLegacyRepeat)
    default:
        Issue.record("Expected disabled outcome")
    }

    let scheduled = WakeScheduleUpdatePolicy.evaluate(
        hour: 3,
        minute: 0,
        enabled: true,
        currentScheduleOutput: "",
        planner: planner,
        referenceDate: reference
    )
    switch scheduled {
    case .schedule(let removeLegacyRepeat, let dateTime, let nextWake):
        #expect(!removeLegacyRepeat)
        #expect(!dateTime.isEmpty)
        let expected = DailySchedule.nextRunDate(from: "03:00", referenceDate: reference)
        #expect(nextWake == expected)
    default:
        Issue.record("Expected schedule outcome")
    }

    let unavailable = WakeScheduleUpdatePolicy.evaluate(
        hour: 99,
        minute: 0,
        enabled: true,
        currentScheduleOutput: legacyOutput,
        planner: planner,
        referenceDate: reference
    )
    switch unavailable {
    case .scheduleUnavailable(let removeLegacyRepeat):
        #expect(!removeLegacyRepeat)
    default:
        Issue.record("Expected scheduleUnavailable outcome")
    }
}

@Test func settingsPresentationPolicyCoversPrimaryBranches() {
    let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let scanned = SettingsPresentationPolicy.timeMachineSubtitle(
        osVersion: "15.4",
        scannedAt: scannedAt,
        fullDiskAccessGranted: true
    )
    #expect(scanned.contains("Auto-detected on macOS 15.4"))

    let pendingFDA = SettingsPresentationPolicy.timeMachineSubtitle(
        osVersion: nil,
        scannedAt: nil,
        fullDiskAccessGranted: false
    )
    #expect(pendingFDA.contains("Full Disk Access is required"))

    let pendingGeneric = SettingsPresentationPolicy.timeMachineSubtitle(
        osVersion: nil,
        scannedAt: nil,
        fullDiskAccessGranted: true
    )
    #expect(pendingGeneric.contains("has not completed yet"))

    let requiredMessage = "Full Disk Access required"
    let desiredIdle = SettingsPresentationPolicy.desiredIdleStatus(
        isOrchestratorRunning: false,
        orchestratorPhase: .idle,
        orchestratorStatusMessage: requiredMessage,
        fullDiskAccessGranted: true,
        fullDiskAccessRequiredMessage: requiredMessage
    )
    #expect(desiredIdle == "Idle")

    let running = SettingsPresentationPolicy.desiredIdleStatus(
        isOrchestratorRunning: true,
        orchestratorPhase: .idle,
        orchestratorStatusMessage: requiredMessage,
        fullDiskAccessGranted: true,
        fullDiskAccessRequiredMessage: requiredMessage
    )
    #expect(running == nil)

    let grantedButNoOverride = SettingsPresentationPolicy.desiredIdleStatus(
        isOrchestratorRunning: false,
        orchestratorPhase: .failed,
        orchestratorStatusMessage: "Different status",
        fullDiskAccessGranted: true,
        fullDiskAccessRequiredMessage: requiredMessage
    )
    #expect(grantedButNoOverride == nil)

    let notGranted = SettingsPresentationPolicy.desiredIdleStatus(
        isOrchestratorRunning: false,
        orchestratorPhase: .idle,
        orchestratorStatusMessage: "anything",
        fullDiskAccessGranted: false,
        fullDiskAccessRequiredMessage: requiredMessage
    )
    #expect(notGranted == requiredMessage)
}

@Test func settingsPresentationPolicyFormatsDiagnosticLines() {
    let diagnostics = FullDiskAccessDiagnostics(
        granted: false,
        probes: [
            FullDiskAccessProbe(path: "/a", state: .accessible, detail: nil),
            FullDiskAccessProbe(path: "/b", state: .permissionDenied, detail: "denied"),
            FullDiskAccessProbe(path: "/c", state: .otherError, detail: nil),
            FullDiskAccessProbe(path: "/d", state: .permissionDenied, detail: "nope"),
            FullDiskAccessProbe(path: "/e", state: .permissionDenied, detail: "blocked"),
            FullDiskAccessProbe(path: "/f", state: .permissionDenied, detail: "blocked2")
        ]
    )
    let lines = SettingsPresentationPolicy.fullDiskAccessDiagnosticLines(from: diagnostics)
    #expect(lines.count == 4)
    #expect(lines[0].contains("/b"))
    #expect(lines[1].contains("no detail"))

    let empty = SettingsPresentationPolicy.fullDiskAccessDiagnosticLines(
        from: FullDiskAccessDiagnostics(granted: true, probes: [FullDiskAccessProbe(path: "/ok", state: .accessible, detail: nil)])
    )
    #expect(empty == ["No denied probe path captured yet."])
}

@Test func fullDiskAccessDiagnosticsEvaluatorCoversGrantingLogic() {
    let tmDenied = FullDiskAccessProbe(path: "tmutil", state: .permissionDenied, detail: "requires FDA")
    let tmAccessible = FullDiskAccessProbe(path: "tmutil", state: .accessible, detail: nil)

    let deniedByTm = FullDiskAccessDiagnosticsEvaluator.evaluate(
        tmutilProbe: tmDenied,
        pathProbes: [FullDiskAccessProbe(path: "/a", state: .accessible, detail: nil)]
    )
    #expect(!deniedByTm.granted)
    #expect(deniedByTm.probes.count == 1)

    let deniedByPath = FullDiskAccessDiagnosticsEvaluator.evaluate(
        tmutilProbe: tmAccessible,
        pathProbes: [FullDiskAccessProbe(path: "/a", state: .permissionDenied, detail: "x")]
    )
    #expect(!deniedByPath.granted)

    let granted = FullDiskAccessDiagnosticsEvaluator.evaluate(
        tmutilProbe: tmAccessible,
        pathProbes: [FullDiskAccessProbe(path: "/a", state: .accessible, detail: nil)]
    )
    #expect(granted.granted)

    let allMissing = FullDiskAccessDiagnosticsEvaluator.evaluate(
        tmutilProbe: tmAccessible,
        pathProbes: [FullDiskAccessProbe(path: "/a", state: .missing, detail: nil)]
    )
    #expect(!allMissing.granted)

    let existingButUnreadable = FullDiskAccessDiagnosticsEvaluator.evaluate(
        tmutilProbe: tmAccessible,
        pathProbes: [FullDiskAccessProbe(path: "/a", state: .otherError, detail: "EIO")]
    )
    #expect(!existingButUnreadable.granted)
}

@Test func pathPatternMatcherCoversMatchAndDefaultCoverage() {
    #expect(PathPatternMatcher.matches(path: "/Users/da/.Trash/file", pattern: "*/.Trash/*"))
    #expect(!PathPatternMatcher.matches(path: "/Users/da/Documents/file", pattern: "*/.Trash/*"))

    let directCovered = PathPatternMatcher.isCoveredByDefaultPatterns(
        path: "/Users/da/.Trash/file",
        defaultPatterns: ["*/.Trash/*"]
    )
    #expect(directCovered)

    // This path itself may not match "/tmp/target/*", but the synthetic child should.
    let childProbeCovered = PathPatternMatcher.isCoveredByDefaultPatterns(
        path: "/tmp/target",
        defaultPatterns: ["/tmp/target/*"]
    )
    #expect(childProbeCovered)

    let childProbeCoveredWithTrailingSlash = PathPatternMatcher.isCoveredByDefaultPatterns(
        path: "/tmp/target/",
        defaultPatterns: ["/tmp/target/*"]
    )
    #expect(childProbeCoveredWithTrailingSlash)

    let notCovered = PathPatternMatcher.isCoveredByDefaultPatterns(
        path: "/Users/da/Documents",
        defaultPatterns: ["*/Caches/*", "*/.Trash/*"]
    )
    #expect(!notCovered)
}

@Test func archiveProgressProcessorCoversCheckpointMetricsAndThroughputLines() {
    let now = Date(timeIntervalSince1970: 100)
    let prior = ArchiveProgressProcessorState(
        lastSampleAt: Date(timeIntervalSince1970: 96),
        lastOriginalBytes: 1_024,
        lastDeduplicatedBytes: 256
    )
    let existingStats = ArchiveLiveStats(
        originalBytes: 1_024,
        compressedBytes: 800,
        deduplicatedBytes: 256,
        fileCount: 10,
        readRateBytesPerSecond: 10,
        writeRateBytesPerSecond: 4,
        throughputText: nil,
        etaText: nil,
        latestLine: "old"
    )

    let checkpoint = ArchiveProgressProcessor.process(
        line: "Creating archive: Saving files cache",
        now: now,
        currentStats: existingStats,
        state: prior
    )
    #expect(checkpoint?.statusMessage == "Checkpointing cache...")
    #expect(checkpoint?.stats?.latestLine == "Creating archive: Saving files cache")

    let metrics = ArchiveProgressProcessor.process(
        line: "4 KiB O 2 KiB C 1 KiB D 20 N 15 MiB/s ETA 00:42",
        now: now,
        currentStats: existingStats,
        state: prior
    )
    #expect(metrics?.stats?.originalBytes == 4_096)
    #expect(metrics?.stats?.compressedBytes == 2_048)
    #expect(metrics?.stats?.deduplicatedBytes == 1_024)
    #expect(metrics?.stats?.fileCount == 20)
    #expect(metrics?.stats?.readRateBytesPerSecond == 768)
    #expect(metrics?.stats?.writeRateBytesPerSecond == 192)
    #expect(metrics?.stats?.throughputText == "15 MiB/s")
    #expect(metrics?.stats?.etaText == "ETA 00:42")

    let throughputOnly = ArchiveProgressProcessor.process(
        line: "30 MiB/s ETA 00:15 files done",
        now: now,
        currentStats: existingStats,
        state: prior
    )
    #expect(throughputOnly?.statusMessage == "Creating archive: 30 MiB/s ETA 00:15 files done")
    #expect(throughputOnly?.stats?.throughputText == "30 MiB/s")
    #expect(throughputOnly?.stats?.etaText == "ETA 00:15")

    let noStatsToRefresh = ArchiveProgressProcessor.process(
        line: "30 MiB/s ETA 00:15 files done",
        now: now,
        currentStats: nil,
        state: prior
    )
    #expect(noStatsToRefresh?.stats == nil)

    let ignored = ArchiveProgressProcessor.process(
        line: "completely unrelated output",
        now: now,
        currentStats: existingStats,
        state: prior
    )
    #expect(ignored == nil)
}

@Test func backupRunMetricsFactoryBuildsCompletedAndFailedMetrics() {
    let startedAt = Date(timeIntervalSince1970: 100)
    let finishedAt = Date(timeIntervalSince1970: 220)
    let output = """
    This archive: 2 GiB 1 GiB 512 MiB
    All archives: 3 GiB 2 GiB 1 GiB
    """

    let completed = BackupRunMetricsFactory.completedRunMetrics(
        createOutput: output,
        repositoryStoredBytes: 9_999,
        backupDuration: 80,
        pruneDuration: 20,
        compactDuration: 10,
        startedAt: startedAt,
        finishedAt: finishedAt
    )
    #expect(completed.readFromSourceBytes == 2_147_483_648)
    #expect(completed.writtenToRepoBytes == 536_870_912)
    #expect(completed.repositoryStoredBytes == 9_999)
    #expect(completed.totalDurationSeconds == 120)

    let completedWithoutOutput = BackupRunMetricsFactory.completedRunMetrics(
        createOutput: nil,
        repositoryStoredBytes: nil,
        backupDuration: nil,
        pruneDuration: nil,
        compactDuration: nil,
        startedAt: startedAt,
        finishedAt: finishedAt
    )
    #expect(completedWithoutOutput.readFromSourceBytes == nil)
    #expect(completedWithoutOutput.writtenToRepoBytes == nil)

    let failed = BackupRunMetricsFactory.failedRunMetrics(
        startedAt: startedAt,
        finishedAt: finishedAt,
        backupDuration: 10,
        pruneDuration: nil,
        compactDuration: nil
    )
    #expect(failed.readFromSourceBytes == nil)
    #expect(failed.writtenToRepoBytes == nil)
    #expect(failed.repositoryStoredBytes == nil)
    #expect(failed.totalDurationSeconds == 120)
}

private func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    calendar: Calendar
) -> Date {
    let components = DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    )
    return components.date!
}
