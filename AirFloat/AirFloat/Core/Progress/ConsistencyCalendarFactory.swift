import Foundation

enum ConsistencyCalendarFactory {
    static func buildCurrentMonth(
        sessions: [WorkoutSessionRecord],
        schedule: ProgramSchedule = .default,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ConsistencyCalendarMonthModel {
        var workingCalendar = calendar
        workingCalendar.firstWeekday = 2

        let currentComponents = workingCalendar.dateComponents([.year, .month], from: now)
        let year = currentComponents.year ?? 1970
        let month = currentComponents.month ?? 1

        return buildMonth(
            year: year,
            month: month,
            sessions: sessions,
            schedule: schedule,
            calendar: workingCalendar,
            now: now
        )
    }

    static func buildMonth(
        year: Int,
        month: Int,
        sessions: [WorkoutSessionRecord],
        schedule: ProgramSchedule = .default,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ConsistencyCalendarMonthModel {
        var workingCalendar = calendar
        workingCalendar.firstWeekday = 2

        let monthStart = workingCalendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
        let dayRange = workingCalendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1
        let todayStart = workingCalendar.startOfDay(for: now)
        let groupedSessions = Dictionary(grouping: sessions) { session in
            workingCalendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(session.timestampMs) / 1000.0))
        }

        let days = dayRange.map { day -> ConsistencyCalendarDayModel in
            let date = workingCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? monthStart
            let startOfDay = workingCalendar.startOfDay(for: date)
            let daySessions = groupedSessions[startOfDay, default: []].sorted { $0.timestampMs < $1.timestampMs }
            let mappedSessions = daySessions.map { session in
                CalendarDaySessionModel(
                    exerciseName: session.exerciseKey.displayName,
                    completionRate: session.completionRate.clamped(to: 0...100),
                    reps: max(0, session.reps)
                )
            }
            let averageScore = daySessions.isEmpty
                ? 0
                : daySessions.map { $0.completionRate.clamped(to: 0...100) }.reduce(0, +) / daySessions.count
            let isPlannedRest = schedule.plannedDayType(for: startOfDay, calendar: workingCalendar) == .rest
            let isMissed = startOfDay < todayStart && !isPlannedRest && daySessions.isEmpty
            let state = resolveState(
                date: startOfDay,
                today: todayStart,
                hasTraining: !daySessions.isEmpty,
                averageScore: averageScore,
                isPlannedRest: isPlannedRest,
                isMissed: isMissed
            )

            return ConsistencyCalendarDayModel(
                startOfDayMs: Int64(startOfDay.timeIntervalSince1970 * 1000),
                dayNumber: day,
                state: state,
                sessions: mappedSessions,
                averageScore: averageScore,
                isPlannedRest: isPlannedRest,
                isMissed: isMissed
            )
        }

        let trainedDays = days.filter { !$0.sessions.isEmpty }.count
        let missedDays = days.filter(\.isMissed).count
        let adherence = adherenceScore(days)

        return ConsistencyCalendarMonthModel(
            monthTitle: monthTitle(monthStart, calendar: workingCalendar),
            summaryText: "\(trainedDays) workouts - \(missedDays) misses",
            streakText: "\(adherenceStreak(days, calendar: workingCalendar, today: todayStart)) day streak",
            adherenceText: "\(adherence)% adherence",
            weekdayLabels: ["M", "T", "W", "T", "F", "S", "S"],
            leadingEmptyDays: leadingEmptyDays(for: monthStart, calendar: workingCalendar),
            days: days
        )
    }

    private static func resolveState(
        date: Date,
        today: Date,
        hasTraining: Bool,
        averageScore: Int,
        isPlannedRest: Bool,
        isMissed: Bool
    ) -> CalendarDayState {
        if hasTraining && averageScore >= 90 { return .trainedPerfect }
        if hasTraining && averageScore >= 80 { return .trainedHigh }
        if hasTraining && averageScore >= 70 { return .trainedMid }
        if hasTraining { return .trainedLow }
        if date == today && !isPlannedRest { return .todayEmpty }
        if isMissed { return .missed }
        if isPlannedRest { return .plannedRest }
        if date > today { return .future }
        return .rest
    }

    private static func leadingEmptyDays(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private static func monthTitle(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    private static func adherenceScore(_ days: [ConsistencyCalendarDayModel]) -> Int {
        let targetDays = days.filter { day in
            day.state != .future &&
                day.state != .todayEmpty &&
                !day.isPlannedRest
        }
        guard !targetDays.isEmpty else { return 100 }
        let trained = targetDays.filter { !$0.sessions.isEmpty }.count
        return Int((Double(trained) / Double(targetDays.count)) * 100.0)
    }

    private static func adherenceStreak(
        _ days: [ConsistencyCalendarDayModel],
        calendar: Calendar,
        today: Date
    ) -> Int {
        let ordered = days
            .filter { Date(timeIntervalSince1970: TimeInterval($0.startOfDayMs) / 1000.0) <= today }
            .sorted { $0.startOfDayMs > $1.startOfDayMs }

        var streak = 0
        for day in ordered {
            if day.isMissed { break }
            if !day.sessions.isEmpty || day.isPlannedRest || day.state == .todayEmpty {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
