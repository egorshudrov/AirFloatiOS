import Foundation

final class ProgramScheduleRepository {
    private let defaults: UserDefaults
    private let restDaysKey: String
    private let dateOverridesKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        restDaysKey: String = "airfloat.program.restDaysOfWeek.v1",
        dateOverridesKey: String = "airfloat.program.dateOverrides.v1"
    ) {
        self.defaults = defaults
        self.restDaysKey = restDaysKey
        self.dateOverridesKey = dateOverridesKey
    }

    func loadSchedule() -> ProgramSchedule {
        ProgramSchedule(
            restDaysOfWeek: loadRestDays(),
            dateOverrides: loadDateOverrides()
        )
    }

    func loadRestDays() -> Set<ProgramWeekday> {
        guard defaults.object(forKey: restDaysKey) != nil else {
            return ProgramWeekday.defaultRestDays
        }

        let values = defaults.stringArray(forKey: restDaysKey) ?? []
        return Set(values.compactMap(ProgramWeekday.init(rawValue:)))
    }

    func saveRestDays(_ restDays: Set<ProgramWeekday>) {
        defaults.set(
            restDays.map(\.rawValue).sorted(),
            forKey: restDaysKey
        )
    }

    func loadDateOverrides() -> [ProgramScheduleDate: PlannedDayType] {
        guard let data = defaults.data(forKey: dateOverridesKey) else {
            return [:]
        }

        return (try? decoder.decode([ProgramScheduleDate: PlannedDayType].self, from: data)) ?? [:]
    }

    func saveDateOverrides(_ overrides: [ProgramScheduleDate: PlannedDayType]) {
        guard let data = try? encoder.encode(overrides) else {
            return
        }

        defaults.set(data, forKey: dateOverridesKey)
    }

    func saveSchedule(_ schedule: ProgramSchedule) {
        saveRestDays(schedule.restDaysOfWeek)
        saveDateOverrides(schedule.dateOverrides)
    }

    func setDateOverride(
        date: ProgramScheduleDate,
        type: PlannedDayType
    ) {
        var overrides = loadDateOverrides()
        overrides[date] = type
        saveDateOverrides(overrides)
    }

    func clearDateOverride(date: ProgramScheduleDate) {
        var overrides = loadDateOverrides()
        guard overrides.removeValue(forKey: date) != nil else {
            return
        }
        saveDateOverrides(overrides)
    }
}
