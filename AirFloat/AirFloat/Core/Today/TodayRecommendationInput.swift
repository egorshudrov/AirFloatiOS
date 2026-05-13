import Foundation

struct TodayRecommendationInput: Sendable {
    let sessions: [WorkoutSessionRecord]
    let schedule: ProgramSchedule
    let calendar: Calendar
    let now: Date
    let timeZone: TimeZone

    init(
        sessions: [WorkoutSessionRecord],
        schedule: ProgramSchedule = .default,
        calendar: Calendar = .current,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        self.sessions = sessions
        self.schedule = schedule
        self.calendar = calendar
        self.now = now
        self.timeZone = timeZone
    }
}
