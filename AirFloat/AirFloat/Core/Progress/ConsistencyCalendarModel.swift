import Foundation

enum CalendarDayState: String, Codable, Equatable, Sendable {
    case trainedPerfect
    case trainedHigh
    case trainedMid
    case trainedLow
    case plannedRest
    case missed
    case rest
    case future
    case todayEmpty
}

struct CalendarDaySessionModel: Codable, Equatable, Sendable {
    let exerciseName: String
    let completionRate: Int
    let reps: Int
}

struct ConsistencyCalendarDayModel: Identifiable, Codable, Equatable, Sendable {
    var id: Int64 { startOfDayMs }

    let startOfDayMs: Int64
    let dayNumber: Int
    let state: CalendarDayState
    let sessions: [CalendarDaySessionModel]
    let averageScore: Int
    let isPlannedRest: Bool
    let isMissed: Bool
}

struct ConsistencyCalendarMonthModel: Codable, Equatable, Sendable {
    let monthTitle: String
    let summaryText: String
    let streakText: String
    let adherenceText: String
    let weekdayLabels: [String]
    let leadingEmptyDays: Int
    let days: [ConsistencyCalendarDayModel]
}
