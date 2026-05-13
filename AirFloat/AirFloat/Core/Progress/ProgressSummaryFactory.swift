import Foundation

enum ProgressSummaryFactory {
    static func build(
        sessions: [WorkoutSessionRecord],
        timeZone: TimeZone = .current
    ) -> ProgressSummaryModel {
        let sortedSessions = sessions.sorted { $0.timestampMs > $1.timestampMs }

        guard let latest = sortedSessions.first else {
            return ProgressSummaryModel(
                title: "Training summary",
                sessionCountText: "No saved sessions",
                repCountText: "0 reps",
                attemptBalanceText: "0 clean · 0 missed",
                latestSessionText: "Finish a Live session to start the Progress summary."
            )
        }

        let totalReps = sortedSessions.reduce(0) { $0 + $1.reps }
        let cleanAttempts = sortedSessions.reduce(0) { $0 + $1.successfulAttempts }
        let missedAttempts = sortedSessions.reduce(0) { $0 + $1.failedAttempts }

        return ProgressSummaryModel(
            title: "Training summary",
            sessionCountText: sessionCountText(sortedSessions.count),
            repCountText: "\(totalReps) total \(totalReps == 1 ? "rep" : "reps")",
            attemptBalanceText: "\(cleanAttempts) clean · \(missedAttempts) missed",
            latestSessionText: latestSessionText(latest, timeZone: timeZone)
        )
    }

    private static func sessionCountText(_ count: Int) -> String {
        "\(count) saved \(count == 1 ? "session" : "sessions")"
    }

    private static func latestSessionText(
        _ session: WorkoutSessionRecord,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd MMM"

        let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.timestampMs) / 1000.0))
            .uppercased(with: formatter.locale)

        return "Latest: \(session.exerciseKey.displayName) · \(date) · \(session.completionRate)%"
    }
}
