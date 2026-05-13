import Foundation

enum LatestSessionMapFactory {
    static func build(
        session: WorkoutSessionRecord,
        timeZone: TimeZone = .current
    ) -> LatestSessionMapModel {
        let attemptsResult = attemptsForDisplay(session: session)
        let attempts = attemptsResult.attempts
        let isLegacy = attemptsResult.isLegacy
        let selectedIndex = defaultSelectedIndex(for: attempts)

        let selectedAttempt =
            attempts.indices.contains(selectedIndex)
            ? detail(for: attempts[selectedIndex], isLegacy: isLegacy)
            : LatestAttemptDetailModel(
                title: "ATTEMPT --",
                badge: "NO DATA",
                tone: .neutral,
                meta: "No per-attempt telemetry was stored for this session.",
                detail: "Start a new workout and every rep will land on this map."
            )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd MMM"

        let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.timestampMs) / 1000.0))
            .uppercased(with: formatter.locale)
        let attemptSummary =
            attempts.isEmpty
            ? "NO ATTEMPTS"
            : "\(attempts.count) \(attempts.count == 1 ? "ATTEMPT" : "ATTEMPTS")"

        var sessionMeta = "\(date) · \(attemptSummary)"
        if isLegacy {
            sessionMeta += " · LEGACY"
        }

        return LatestSessionMapModel(
            sessionTitle: session.exerciseKey.displayName.uppercased(with: formatter.locale),
            sessionBadge: "\(session.completionRate)%",
            sessionMeta: sessionMeta,
            sessionStatus: session.completed ? "COMPLETE" : "PARTIAL",
            attempts: attempts,
            selectedIndex: selectedIndex,
            selectedAttempt: selectedAttempt,
            isLegacy: isLegacy
        )
    }

    static func attemptsForDisplay(
        session: WorkoutSessionRecord
    ) -> (attempts: [WorkoutSessionAttemptRecord], isLegacy: Bool) {
        if !session.attempts.isEmpty {
            return (session.attempts.sorted { $0.index < $1.index }, false)
        }

        let totalAttempts = session.successfulAttempts + session.failedAttempts
        if totalAttempts <= 0 {
            return ([], true)
        }

        let durationStep = max(0, session.durationMs / Int64(totalAttempts))
        let kcalStep = totalAttempts > 0 ? session.estimatedKcal / Double(totalAttempts) : 0

        let fallback = (0..<totalAttempts).map { zeroBasedIndex in
            let success = zeroBasedIndex < session.successfulAttempts
            return WorkoutSessionAttemptRecord(
                index: zeroBasedIndex + 1,
                repSnapshot: success ? min(zeroBasedIndex + 1, max(session.reps, 1)) : max(session.reps, 0),
                success: success,
                elapsedMs: durationStep * Int64(zeroBasedIndex + 1),
                estimatedKcal: kcalStep * Double(zeroBasedIndex + 1),
                detail: success
                    ? "Legacy clean rep reconstructed from session totals."
                    : "Legacy missed attempt reconstructed from session totals."
            )
        }

        return (fallback, true)
    }

    static func defaultSelectedIndex(for attempts: [WorkoutSessionAttemptRecord]) -> Int {
        if attempts.isEmpty {
            return -1
        }

        return attempts.lastIndex(where: { !$0.success }) ?? (attempts.count - 1)
    }

    static func detail(
        for attempt: WorkoutSessionAttemptRecord,
        isLegacy: Bool
    ) -> LatestAttemptDetailModel {
        let tone: LatestAttemptTone = attempt.success ? .clean : .miss
        let repMeta =
            attempt.success
            ? "Rep \(max(attempt.repSnapshot, 1)) locked"
            : "Rep count held at \(max(attempt.repSnapshot, 0))"
        let meta = "\(repMeta) • \(formatDuration(attempt.elapsedMs)) • \(formatKcal(attempt.estimatedKcal))"

        return LatestAttemptDetailModel(
            title: "ATTEMPT \(String(format: "%02d", attempt.index))",
            badge: attempt.success ? "CLEAN" : "MISS",
            tone: tone,
            meta: meta,
            detail: isLegacy
                ? "\(attempt.detail) Exact order was reconstructed from old session totals."
                : attempt.detail
        )
    }

    private static func formatDuration(_ durationMs: Int64) -> String {
        let totalSeconds = Int(durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func formatKcal(_ estimatedKcal: Double) -> String {
        String(format: "%.2f KCAL", locale: Locale(identifier: "en_US_POSIX"), estimatedKcal)
    }
}
