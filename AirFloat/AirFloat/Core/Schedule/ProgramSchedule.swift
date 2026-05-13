import Foundation

struct ProgramSchedule: Codable, Equatable, Sendable {
    let restDaysOfWeek: Set<ProgramWeekday>
    let dateOverrides: [ProgramScheduleDate: PlannedDayType]

    static let `default` = ProgramSchedule(
        restDaysOfWeek: ProgramWeekday.defaultRestDays,
        dateOverrides: [:]
    )

    func plannedDayType(for date: Date, calendar: Calendar = .current) -> PlannedDayType {
        let scheduleDate = ProgramScheduleDate(date: date, calendar: calendar)
        if let override = dateOverrides[scheduleDate] {
            return override
        }

        let weekday = ProgramWeekday.from(date: date, calendar: calendar)
        return restDaysOfWeek.contains(weekday) ? .rest : .train
    }
}
