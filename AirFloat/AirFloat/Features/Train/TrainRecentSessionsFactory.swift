import Foundation

enum TrainRecentSessionsFactory {
    static func build(
        sessions: [WorkoutSessionRecord],
        calendar: Calendar = .current
    ) -> [TrainRecentSessionModel] {
        sessions
            .sorted { $0.timestampMs > $1.timestampMs }
            .prefix(4)
            .map { session in
                TrainRecentSessionModel(
                    id: session.id,
                    title: title(for: session),
                    meta: meta(for: session, calendar: calendar)
                )
            }
    }

    private static func title(for session: WorkoutSessionRecord) -> String {
        ExerciseCatalog.item(forPresetKey: session.presetKey)?.displayName ?? session.exerciseKey.displayName
    }

    private static func meta(
        for session: WorkoutSessionRecord,
        calendar: Calendar
    ) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(session.timestampMs) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM"

        return "\(formatter.string(from: date).uppercased()) · \(session.reps) REPS"
    }
}
