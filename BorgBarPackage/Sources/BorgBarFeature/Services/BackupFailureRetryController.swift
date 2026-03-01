import Foundation

@MainActor
final class BackupFailureRetryController {
    private var retryTask: Task<Void, Never>?
    private var retryScheduledAt: Date?

    func schedule(
        plan: BackupFailureRetryPlan,
        trigger: BackupTrigger,
        isRunning: @escaping @MainActor () -> Bool,
        onRetry: @escaping @MainActor () -> Void
    ) {
        clearWithoutLogging()

        retryScheduledAt = plan.retryAt
        let timestamp = plan.retryAt.formatted(date: .abbreviated, time: .shortened)
        let cutoffText = plan.cutoffAt.formatted(date: .abbreviated, time: .shortened)
        AppLogger.info("Backup failed (\(trigger.rawValue)); scheduling retry for \(timestamp) (retry window closes at \(cutoffText))")

        retryTask = Task { [weak self] in
            guard let self else { return }

            let delay = max(0, plan.retryAt.timeIntervalSinceNow)
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }

            while await MainActor.run(body: { isRunning() }) {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    return
                }
            }

            await MainActor.run {
                guard self.retryScheduledAt == plan.retryAt else { return }
                self.clearWithoutLogging()

                if Date() >= plan.cutoffAt {
                    let cutoff = plan.cutoffAt.formatted(date: .abbreviated, time: .shortened)
                    AppLogger.info("Failure retry window ended at \(cutoff); waiting for scheduled backup")
                    return
                }

                onRetry()
            }
        }
    }

    func clear(reason: String) {
        guard retryTask != nil || retryScheduledAt != nil else { return }
        clearWithoutLogging()
        AppLogger.info("Cleared scheduled failure retry: \(reason)")
    }

    private func clearWithoutLogging() {
        retryTask?.cancel()
        retryTask = nil
        retryScheduledAt = nil
    }
}
