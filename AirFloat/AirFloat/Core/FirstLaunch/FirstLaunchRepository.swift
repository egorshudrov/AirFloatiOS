import Foundation

final class FirstLaunchRepository {
    private let defaults: UserDefaults
    private let programScheduleRepository: ProgramScheduleRepository
    private let completedKey: String
    private let completedAtMsKey: String
    private let completedVersionKey: String
    private let currentOnboardingVersion: Int

    init(
        defaults: UserDefaults = .standard,
        programScheduleRepository: ProgramScheduleRepository = ProgramScheduleRepository(),
        completedKey: String = "airfloat.firstLaunch.onboardingCompleted.v1",
        completedAtMsKey: String = "airfloat.firstLaunch.completedAtMs.v1",
        completedVersionKey: String = "airfloat.firstLaunch.completedVersion.v1",
        currentOnboardingVersion: Int = 2
    ) {
        self.defaults = defaults
        self.programScheduleRepository = programScheduleRepository
        self.completedKey = completedKey
        self.completedAtMsKey = completedAtMsKey
        self.completedVersionKey = completedVersionKey
        self.currentOnboardingVersion = currentOnboardingVersion
    }

    func loadState() -> FirstLaunchState {
        let completed = defaults.bool(forKey: completedKey)
        let completedVersion = defaults.integer(forKey: completedVersionKey)
        let completedAtMs = defaults.object(forKey: completedAtMsKey) == nil
            ? nil
            : Int64(defaults.integer(forKey: completedAtMsKey))

        return FirstLaunchState(
            shouldShowFirstLaunch: !completed || completedVersion < currentOnboardingVersion,
            completedAtMs: completedAtMs,
            completedVersion: completedVersion
        )
    }

    func shouldShowFirstLaunch() -> Bool {
        loadState().shouldShowFirstLaunch
    }

    func markCompleted() {
        defaults.set(true, forKey: completedKey)
        defaults.set(Int64(Date().timeIntervalSince1970 * 1_000), forKey: completedAtMsKey)
        defaults.set(currentOnboardingVersion, forKey: completedVersionKey)
    }

    func completeWithWeeklyProgram(restDays: Set<ProgramWeekday>) {
        programScheduleRepository.saveRestDays(restDays)
        markCompleted()
    }

    func resetForDebug() {
        defaults.removeObject(forKey: completedKey)
        defaults.removeObject(forKey: completedAtMsKey)
        defaults.removeObject(forKey: completedVersionKey)
    }
}
