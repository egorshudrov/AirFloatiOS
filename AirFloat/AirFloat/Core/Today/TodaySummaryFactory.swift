import Foundation

enum TodaySummaryFactory {
    static func build(input: TodayRecommendationInput) -> TodaySummaryModel {
        build(
            sessions: input.sessions,
            timeZone: input.timeZone
        )
    }

    static func build(
        sessions: [WorkoutSessionRecord],
        timeZone: TimeZone = .current
    ) -> TodaySummaryModel {
        let sortedSessions = sessions.sorted { $0.timestampMs > $1.timestampMs }
        let recommendedExercise = ExerciseCatalog.defaultExercise.key

        guard let latest = sortedSessions.first else {
            return TodaySummaryModel(
                isFirstSession: true,
                headline: "Start your first AirFloat session",
                subheadline: "Build the first saved workout loop with one focused Barbell Press session.",
                recommendedExercise: recommendedExercise,
                primaryActionTitle: "Start Barbell Press",
                sessionCountText: "No sessions saved yet",
                latestSessionText: "Progress will unlock after the first saved session."
            )
        }

        return TodaySummaryModel(
            isFirstSession: false,
            headline: "Your loop is active",
            subheadline: "Latest saved session is ready in Progress. Keep the rhythm with another Barbell Press set.",
            recommendedExercise: recommendedExercise,
            primaryActionTitle: "Train Barbell Press",
            sessionCountText: sessionCountText(sortedSessions.count),
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

        return "\(session.exerciseKey.displayName) · \(date) · \(session.reps)/\(session.goalReps) reps · \(session.completionRate)%"
    }
}
