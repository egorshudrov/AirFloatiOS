import Foundation

struct CoreCheckFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CoreCheckFailure(description: message)
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw CoreCheckFailure(description: "\(message). Expected \(expected), got \(actual)")
    }
}

func runExerciseCatalogChecks() throws {
    try checkEqual(ExerciseCatalog.all.count, 5, "Exercise catalog should expose five Android-aligned exercises")
    try checkEqual(ExerciseCatalog.defaultExercise.key, .pressBarbell, "Default exercise should remain Barbell Press")

    let expectedKeys: [ExerciseKey] = [
        .pressBarbell,
        .pressDumbbell,
        .squatBeta,
        .pushup,
        .situp
    ]
    try checkEqual(ExerciseCatalog.all.map(\.key), expectedKeys, "Exercise catalog order changed unexpectedly")

    for exercise in ExerciseCatalog.all {
        try checkEqual(ExerciseCatalog.item(for: exercise.key), exercise, "Lookup by ExerciseKey failed for \(exercise.key.rawValue)")
        try checkEqual(ExerciseCatalog.item(forPresetKey: exercise.presetKey), exercise, "Lookup by preset key failed for \(exercise.presetKey)")
        try checkEqual(exercise.presetKey, exercise.key.rawValue, "Preset key should match ExerciseKey raw value for \(exercise.key.rawValue)")
    }

    let squat = ExerciseCatalog.item(for: .squatBeta)
    try checkEqual(squat.displayName, "Squats", "Squat display name changed")
    try checkEqual(squat.shortLabel, "SQ", "Squat short label changed")
    try checkEqual(squat.progressTabLabel, "SQUATS", "Squat progress tab label changed")
    try check(!squat.goalRepsEnabled, "Squat beta should keep goal reps disabled until runtime is validated")
}

func runStartRequestChecks() throws {
    let defaultRequest = WorkoutSessionStartRequest.defaultBarbellPress
    try checkEqual(defaultRequest.exercise.key, .pressBarbell, "Default start request should use Barbell Press")
    try checkEqual(defaultRequest.goalReps, 0, "Default start request should be a free session")
    try checkEqual(defaultRequest.goalDisplayText, "Goal: Free session", "Free goal display text changed")

    let goalRequest = WorkoutSessionStartRequest(
        exercise: ExerciseCatalog.item(for: .pressBarbell),
        goalReps: 10
    )
    try checkEqual(goalRequest.goalDisplayText, "Goal: 10 reps", "Goal reps display text changed")
}

func runTrainAvailabilityChecks() throws {
    let expected: [ExerciseKey: TrainExerciseAvailability] = [
        .pressBarbell: .ready,
        .squatBeta: .betaValidation,
        .pressDumbbell: .ready,
        .pushup: .betaValidation,
        .situp: .betaValidation
    ]

    for exercise in ExerciseCatalog.all {
        let availability = TrainExerciseAvailability.availability(for: exercise)
        try checkEqual(availability, expected[exercise.key], "Train availability changed for \(exercise.key.rawValue)")
    }

    try check(TrainExerciseAvailability.ready.canStart, "Ready exercises should be startable")
    try check(TrainExerciseAvailability.betaValidation.canStart, "Beta validation exercises should remain startable")
    try check(!TrainExerciseAvailability.planned.canStart, "Planned exercises should not be startable")
    try checkEqual(TrainExerciseAvailability.ready.rowLabel, "Ready", "Ready row label changed")
    try checkEqual(TrainExerciseAvailability.betaValidation.rowLabel, "Beta validation", "Beta row label changed")
    try checkEqual(TrainExerciseAvailability.planned.rowLabel, "Planned", "Planned row label changed")
    try checkEqual(TrainExerciseAvailability.ready.startButtonTitle, "Start Session", "Ready start title changed")
    try checkEqual(TrainExerciseAvailability.betaValidation.startButtonTitle, "Start Beta Session", "Beta start title changed")
    try checkEqual(TrainExerciseAvailability.planned.startButtonTitle, "Start Session", "Planned start title changed")
}

func runLiveExerciseTrackingPipelineChecks() throws {
    try checkEqual(
        LiveExerciseTrackingPipeline.pipeline(for: .pressBarbell),
        .barbellPressCounter,
        "Barbell Press should use the barbell press counter"
    )
    try checkEqual(
        LiveExerciseTrackingPipeline.pipeline(for: .pressDumbbell),
        .barbellPressCounter,
        "Dumbbell Press should copy the Barbell Press counter pipeline"
    )
    try checkEqual(
        LiveExerciseTrackingPipeline.pipeline(for: .squatBeta),
        .squatCounter,
        "Squat should use the squat counter pipeline"
    )
    try checkEqual(
        LiveExerciseTrackingPipeline.pipeline(for: .pushup),
        .pushupCounter,
        "Push-up should use the push-up counter pipeline"
    )
    try checkEqual(
        LiveExerciseTrackingPipeline.pipeline(for: .situp),
        .situpCounter,
        "Sit-up should use the sit-up counter pipeline"
    )
}

func sampleAttempt(index: Int, success: Bool, repSnapshot: Int) -> WorkoutSessionAttemptRecord {
    WorkoutSessionAttemptRecord(
        index: index,
        repSnapshot: repSnapshot,
        success: success,
        elapsedMs: Int64(index * 1_000),
        estimatedKcal: success ? 0.6 : 0.45,
        detail: success ? "Clean attempt" : "Missed attempt"
    )
}

func sampleSession(
    id: String,
    timestampMs: Int64,
    exerciseKey: ExerciseKey,
    goalReps: Int = 0,
    completed: Bool = false,
    reps: Int = 0,
    successfulAttempts: Int = 0,
    failedAttempts: Int = 0
) -> WorkoutSessionRecord {
    let attempts = (0..<successfulAttempts).map {
        sampleAttempt(index: $0 + 1, success: true, repSnapshot: $0 + 1)
    } + (0..<failedAttempts).map {
        sampleAttempt(index: successfulAttempts + $0 + 1, success: false, repSnapshot: reps)
    }

    return WorkoutSessionRecord(
        id: id,
        timestampMs: timestampMs,
        exerciseKey: exerciseKey,
        presetKey: exerciseKey.rawValue,
        goalReps: goalReps,
        completed: completed,
        reps: reps,
        successfulAttempts: successfulAttempts,
        failedAttempts: failedAttempts,
        durationMs: 30_000,
        estimatedKcal: Double(successfulAttempts) * 0.6 + Double(failedAttempts) * 0.45,
        completionRate: attempts.isEmpty ? 0 : Int((Double(successfulAttempts) / Double(attempts.count) * 100).rounded()),
        attempts: attempts
    )
}

func isolatedDefaults(name: String) throws -> UserDefaults {
    let suiteName = "com.airfloat.core-checks.\(name).\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CoreCheckFailure(description: "Failed to create isolated UserDefaults suite")
    }

    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

func utcDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0
) throws -> Date {
    var components = DateComponents()
    components.calendar = utcCalendar()
    components.timeZone = TimeZone(secondsFromGMT: 0)!
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute

    guard let date = components.date else {
        throw CoreCheckFailure(description: "Failed to build UTC date \(year)-\(month)-\(day)")
    }
    return date
}

func timestampMs(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1_000)
}

func runSessionRepositoryChecks() throws {
    let defaults = try isolatedDefaults(name: "sessions")
    let repository = SessionRepository(
        defaults: defaults,
        storageKey: "airfloat.core-checks.sessions"
    )

    try checkEqual(try repository.loadSessions(), [], "New repository should load an empty session list")
    let initialLatest = try repository.latestSession()
    try check(initialLatest == nil, "New repository should not have a latest session")

    let older = sampleSession(
        id: "older-barbell",
        timestampMs: 1_000,
        exerciseKey: .pressBarbell,
        goalReps: 10,
        completed: false,
        reps: 6,
        successfulAttempts: 6,
        failedAttempts: 1
    )
    let newer = sampleSession(
        id: "newer-squat",
        timestampMs: 2_000,
        exerciseKey: .squatBeta,
        completed: true,
        reps: 8,
        successfulAttempts: 8,
        failedAttempts: 0
    )

    try repository.save(older)
    try repository.save(newer)

    let loaded = try repository.loadSessions()
    try checkEqual(loaded.map(\.id), ["newer-squat", "older-barbell"], "Sessions should load newest first")
    try checkEqual(try repository.latestSession()?.id, "newer-squat", "Latest session should be the newest timestamp")
    try checkEqual(loaded[0].exerciseKey, .squatBeta, "Squat session exercise key should survive persistence")
    try checkEqual(loaded[0].presetKey, ExerciseKey.squatBeta.rawValue, "Squat session preset key should survive persistence")
    try check(loaded[0].completed, "Completed flag should survive persistence")
    try check(!loaded[1].completed, "Partial flag should survive persistence")

    let replacement = sampleSession(
        id: "older-barbell",
        timestampMs: 3_000,
        exerciseKey: .pressBarbell,
        goalReps: 10,
        completed: true,
        reps: 10,
        successfulAttempts: 10,
        failedAttempts: 0
    )
    try repository.save(replacement)

    let replaced = try repository.loadSessions()
    try checkEqual(replaced.map(\.id), ["older-barbell", "newer-squat"], "Saving duplicate id should replace and re-sort")
    try checkEqual(replaced.count, 2, "Duplicate id save should not create an extra record")
    try checkEqual(replaced[0].reps, 10, "Replacement record should persist updated reps")
    try check(replaced[0].completed, "Replacement record should persist updated completion")
}

func runLiveSessionStateChecks() throws {
    var state = LiveSessionState()
    try check(!state.hasActivity, "New live session state should not have activity")
    try checkEqual(state.completionRate, 0, "New live session completion rate should be zero")

    state.startIfNeeded(at: 1_000)
    state.startIfNeeded(at: 2_000)
    try checkEqual(state.startedAtMs, 1_000, "startIfNeeded should preserve the first start timestamp")

    state.recordCleanRepIfNeeded(
        reps: 2,
        nowMs: 4_000,
        detail: "Harness clean rep"
    )
    try check(state.hasActivity, "Clean reps should mark live session as active")
    try checkEqual(state.reps, 2, "Clean rep recording should update reps")
    try checkEqual(state.successfulAttempts, 2, "Clean rep recording should add successful attempts")
    try checkEqual(state.failedAttempts, 0, "Clean rep recording should not add failed attempts")
    try checkEqual(state.attempts.map(\.repSnapshot), [1, 2], "Clean rep attempts should snapshot each rep")
    try checkEqual(state.attempts.map(\.success), [true, true], "Clean rep attempts should be successful")
    try checkEqual(state.completionRate, 100, "All-clean session should have 100 completion rate")

    state.recordCleanRepIfNeeded(
        reps: 2,
        nowMs: 5_000,
        detail: "Duplicate clean rep should not record"
    )
    try checkEqual(state.attempts.count, 2, "Same live rep count should not duplicate clean attempts")

    state.recordRejectedAttempt(
        detail: "Harness missed rep",
        repSnapshot: 2,
        nowMs: 6_000
    )
    try checkEqual(state.reps, 2, "Rejected attempt should not increment reps")
    try checkEqual(state.successfulAttempts, 2, "Rejected attempt should not increment successful attempts")
    try checkEqual(state.failedAttempts, 1, "Rejected attempt should increment failed attempts")
    try checkEqual(state.attempts.last?.success, false, "Rejected attempt should append a failed attempt")
    try checkEqual(state.attempts.last?.detail, "Harness missed rep", "Rejected attempt detail should be preserved")
    try checkEqual(state.completionRate, 66, "Completion rate should floor two clean out of three attempts")

    var seeded = LiveSessionState()
    seeded.seedFromLiveCounterIfNeeded(
        reps: 3,
        durationMs: 9_000,
        detail: "Harness fallback rep"
    )
    try checkEqual(seeded.reps, 3, "Fallback seed should set reps from live counter")
    try checkEqual(seeded.successfulAttempts, 3, "Fallback seed should create successful attempts")
    try checkEqual(seeded.failedAttempts, 0, "Fallback seed should not create failed attempts")
    try checkEqual(seeded.attempts.map(\.elapsedMs), [3_000, 6_000, 9_000], "Fallback seed should distribute elapsed time across duration")

    seeded.seedFromLiveCounterIfNeeded(
        reps: 5,
        durationMs: 10_000,
        detail: "Seed should not run over existing activity"
    )
    try checkEqual(seeded.reps, 3, "Fallback seed should not overwrite existing activity")
    try checkEqual(seeded.attempts.count, 3, "Fallback seed should not append over existing activity")

    seeded.reset()
    try check(!seeded.hasActivity, "Reset should clear activity")
    try checkEqual(seeded.startedAtMs, nil, "Reset should clear start timestamp")
    try checkEqual(seeded.attempts, [], "Reset should clear attempts")
}

func runProgressFactoryChecks() throws {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let explicitSession = sampleSession(
        id: "progress-barbell-explicit",
        timestampMs: 1_700_000_000_000,
        exerciseKey: .pressBarbell,
        goalReps: 3,
        completed: false,
        reps: 2,
        successfulAttempts: 2,
        failedAttempts: 1
    )

    let explicitMap = LatestSessionMapFactory.build(
        session: explicitSession,
        timeZone: timeZone
    )
    try checkEqual(explicitMap.sessionTitle, "BARBELL PRESS", "Progress map should use exercise display title")
    try checkEqual(explicitMap.sessionBadge, "67%", "Progress map should use session completion rate")
    try checkEqual(explicitMap.sessionStatus, "PARTIAL", "Incomplete session should show PARTIAL")
    try check(!explicitMap.isLegacy, "Explicit attempts should not be marked legacy")
    try checkEqual(explicitMap.attempts.count, 3, "Explicit attempts should be displayed")
    try checkEqual(explicitMap.selectedIndex, 2, "Default selected index should prefer the latest miss")
    try checkEqual(explicitMap.selectedAttempt.badge, "MISS", "Selected missed attempt badge should be MISS")
    try checkEqual(explicitMap.selectedAttempt.tone, .miss, "Selected missed attempt tone should be miss")

    let legacySession = WorkoutSessionRecord(
        id: "progress-squat-legacy",
        timestampMs: 1_700_000_100_000,
        exerciseKey: .squatBeta,
        presetKey: ExerciseKey.squatBeta.rawValue,
        goalReps: 0,
        completed: true,
        reps: 4,
        successfulAttempts: 4,
        failedAttempts: 0,
        durationMs: 20_000,
        estimatedKcal: 2.4,
        completionRate: 100,
        attempts: []
    )

    let legacyMap = LatestSessionMapFactory.build(
        session: legacySession,
        timeZone: timeZone
    )
    try checkEqual(legacyMap.sessionTitle, "SQUATS", "Squat progress map title should be SQUATS")
    try checkEqual(legacyMap.sessionStatus, "COMPLETE", "Completed session should show COMPLETE")
    try check(legacyMap.isLegacy, "Missing per-attempt telemetry should be marked legacy")
    try check(legacyMap.sessionMeta.contains("LEGACY"), "Legacy session meta should include LEGACY")
    try checkEqual(legacyMap.attempts.count, 4, "Legacy fallback should reconstruct attempt count")
    try checkEqual(legacyMap.selectedIndex, 3, "All-clean legacy session should select the final attempt")
    try checkEqual(legacyMap.selectedAttempt.badge, "CLEAN", "All-clean selected attempt should be CLEAN")
    try check(legacyMap.selectedAttempt.detail.contains("Exact order was reconstructed"), "Legacy selected detail should explain reconstruction")

    let emptyLegacy = WorkoutSessionRecord(
        id: "progress-empty-legacy",
        timestampMs: 1_700_000_200_000,
        exerciseKey: .pushup,
        presetKey: ExerciseKey.pushup.rawValue,
        goalReps: 0,
        completed: false,
        reps: 0,
        successfulAttempts: 0,
        failedAttempts: 0,
        durationMs: 0,
        estimatedKcal: 0,
        completionRate: 0,
        attempts: []
    )
    let emptyMap = LatestSessionMapFactory.build(session: emptyLegacy, timeZone: timeZone)
    try checkEqual(emptyMap.attempts, [], "No-attempt session should not synthesize attempts")
    try checkEqual(emptyMap.selectedIndex, -1, "No-attempt session should have no selected index")
    try checkEqual(emptyMap.selectedAttempt.badge, "NO DATA", "No-attempt session should show no-data detail")

    let summary = ProgressSummaryFactory.build(
        sessions: [explicitSession, legacySession],
        timeZone: timeZone
    )
    try checkEqual(summary.sessionCountText, "2 saved sessions", "Progress summary session count changed")
    try checkEqual(summary.repCountText, "6 total reps", "Progress summary total reps changed")
    try checkEqual(summary.attemptBalanceText, "6 clean · 1 missed", "Progress summary attempt balance changed")
    try check(summary.latestSessionText.contains("Squats"), "Progress summary should choose newest session for latest text")
    try check(summary.latestSessionText.contains("100%"), "Progress summary latest text should include completion rate")
}

func runScheduleCalendarChecks() throws {
    let calendar = utcCalendar()
    let now = try utcDate(year: 2026, month: 5, day: 4, hour: 12)
    let mayFirst = ProgramScheduleDate(date: try utcDate(year: 2026, month: 5, day: 1), calendar: calendar)
    let maySecond = ProgramScheduleDate(date: try utcDate(year: 2026, month: 5, day: 2), calendar: calendar)

    try checkEqual(ProgramWeekday.from(date: try utcDate(year: 2026, month: 5, day: 4), calendar: calendar), .monday, "Weekday mapping for Monday changed")
    try checkEqual(ProgramWeekday.defaultRestDays, [.saturday, .sunday], "Default weekly rest days changed")

    let schedule = ProgramSchedule(
        restDaysOfWeek: [.saturday, .sunday],
        dateOverrides: [
            mayFirst: .rest,
            maySecond: .train
        ]
    )
    try checkEqual(schedule.plannedDayType(for: try utcDate(year: 2026, month: 5, day: 1), calendar: calendar), .rest, "Date override should turn Friday into rest")
    try checkEqual(schedule.plannedDayType(for: try utcDate(year: 2026, month: 5, day: 2), calendar: calendar), .train, "Date override should turn Saturday into train")
    try checkEqual(schedule.plannedDayType(for: try utcDate(year: 2026, month: 5, day: 3), calendar: calendar), .rest, "Weekly template should keep Sunday as rest")

    let defaults = try isolatedDefaults(name: "schedule")
    let repository = ProgramScheduleRepository(
        defaults: defaults,
        restDaysKey: "airfloat.core-checks.restDays",
        dateOverridesKey: "airfloat.core-checks.dateOverrides"
    )
    try checkEqual(repository.loadRestDays(), [.saturday, .sunday], "New schedule repository should return default rest days")
    repository.saveSchedule(schedule)
    try checkEqual(repository.loadSchedule(), schedule, "Saved schedule should round-trip through repository")
    repository.clearDateOverride(date: mayFirst)
    try checkEqual(repository.loadDateOverrides()[mayFirst], nil, "Clearing date override should remove only that date")
    try checkEqual(repository.loadDateOverrides()[maySecond], .train, "Clearing one date override should preserve other overrides")

    let emptyMonth = ConsistencyCalendarFactory.buildMonth(
        year: 2026,
        month: 5,
        sessions: [],
        schedule: schedule,
        calendar: calendar,
        now: now
    )
    try checkEqual(emptyMonth.monthTitle, "MAY 2026", "Calendar month title changed")
    try checkEqual(emptyMonth.weekdayLabels, ["M", "T", "W", "T", "F", "S", "S"], "Calendar weekday labels changed")
    try checkEqual(emptyMonth.leadingEmptyDays, 4, "May 2026 should start after four leading weekday slots")
    try checkEqual(emptyMonth.days.count, 31, "May 2026 should contain 31 day models")
    try checkEqual(emptyMonth.days[0].state, .plannedRest, "May 1 override rest should be planned rest")
    try checkEqual(emptyMonth.days[1].state, .missed, "May 2 override train before today should be missed")
    try checkEqual(emptyMonth.days[2].state, .plannedRest, "May 3 weekly Sunday rest should be planned rest")
    try checkEqual(emptyMonth.days[3].state, .todayEmpty, "May 4 train day without session should be today empty")
    try checkEqual(emptyMonth.days[4].state, .future, "May 5 should be future")
    try checkEqual(emptyMonth.summaryText, "0 workouts - 1 misses", "Empty calendar summary changed")
    try checkEqual(emptyMonth.streakText, "2 day streak", "Empty calendar streak should count today empty and planned rest before prior miss")

    let morningSession = WorkoutSessionRecord(
        id: "calendar-morning",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 4, hour: 9)),
        exerciseKey: .pressBarbell,
        presetKey: ExerciseKey.pressBarbell.rawValue,
        goalReps: 10,
        completed: true,
        reps: 10,
        successfulAttempts: 10,
        failedAttempts: 0,
        durationMs: 45_000,
        estimatedKcal: 6.0,
        completionRate: 100,
        attempts: []
    )
    let laterSession = WorkoutSessionRecord(
        id: "calendar-later",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 4, hour: 10)),
        exerciseKey: .squatBeta,
        presetKey: ExerciseKey.squatBeta.rawValue,
        goalReps: 0,
        completed: false,
        reps: 7,
        successfulAttempts: 7,
        failedAttempts: 1,
        durationMs: 40_000,
        estimatedKcal: 4.2,
        completionRate: 70,
        attempts: []
    )
    let trainedMonth = ConsistencyCalendarFactory.buildMonth(
        year: 2026,
        month: 5,
        sessions: [laterSession, morningSession],
        schedule: schedule,
        calendar: calendar,
        now: now
    )
    let today = trainedMonth.days[3]
    try checkEqual(today.state, .trainedHigh, "Average 85 score should render as trainedHigh")
    try checkEqual(today.averageScore, 85, "Calendar day average score changed")
    try checkEqual(today.sessions.map(\.exerciseName), ["Barbell Press", "Squats"], "Calendar sessions should sort by timestamp")
    try checkEqual(today.sessions.map(\.completionRate), [100, 70], "Calendar session completion rates changed")
    try checkEqual(today.sessions.map(\.reps), [10, 7], "Calendar session reps changed")
    try checkEqual(trainedMonth.summaryText, "1 workouts - 1 misses", "Trained calendar summary changed")
    try checkEqual(trainedMonth.streakText, "2 day streak", "Trained calendar streak changed")
}

func runSquatExternalRenderingChecks() throws {
    let calendar = utcCalendar()
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let squatSession = sampleSession(
        id: "squat-external-rendering",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 4, hour: 9)),
        exerciseKey: .squatBeta,
        completed: true,
        reps: 8,
        successfulAttempts: 8,
        failedAttempts: 0
    )
    let barbellSession = sampleSession(
        id: "barbell-external-rendering",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 3, hour: 9)),
        exerciseKey: .pressBarbell,
        completed: true,
        reps: 5,
        successfulAttempts: 5,
        failedAttempts: 0
    )

    let progressMap = LatestSessionMapFactory.build(session: squatSession, timeZone: timeZone)
    try checkEqual(progressMap.sessionTitle, "SQUATS", "Squat Progress latest map should not render as Barbell")

    let progressSummary = ProgressSummaryFactory.build(sessions: [barbellSession, squatSession], timeZone: timeZone)
    try check(progressSummary.latestSessionText.contains("Squats"), "Progress summary should show latest Squat session by name")
    try check(!progressSummary.latestSessionText.contains("Barbell Press"), "Progress summary latest text should not leak older Barbell name")

    let recent = TrainRecentSessionsFactory.build(sessions: [barbellSession, squatSession], calendar: calendar)
    try checkEqual(recent.first?.id, "squat-external-rendering", "Train recent sessions should sort Squat as the newest session")
    try checkEqual(recent.first?.title, "Squats", "Train recent sessions should render Squat title")

    let todaySummary = TodaySummaryFactory.build(sessions: [barbellSession, squatSession], timeZone: timeZone)
    try check(todaySummary.latestSessionText.contains("Squats"), "Today latest session text should render Squat title")
    try checkEqual(todaySummary.recommendedExercise, .pressBarbell, "Today recommendation should remain Barbell until recommendation logic is explicitly changed")

    let zones = TodayBodyMapFactory.build(
        sessions: [squatSession],
        calendar: calendar,
        now: try utcDate(year: 2026, month: 5, day: 4, hour: 12)
    )
    let legs = zones.first { $0.zone == .legs }
    try checkEqual(legs?.precision, squatSession.completionRate, "Today legs zone should use Squat precision")
    try checkEqual(legs?.rank, .elite, "Today legs zone should rank clean Squat as elite")
    try checkEqual(legs?.lastSeenLabel, "0D AGO", "Today legs zone should mark same-day Squat as 0D AGO")
    try checkEqual(legs?.exercises.first?.exerciseKey, .squatBeta, "Today legs zone should expose Squat exercise key")
    try checkEqual(legs?.exercises.first?.name, "Squats", "Today legs zone should expose Squat name")
}

func runFirstLaunchRepositoryChecks() throws {
    let defaults = try isolatedDefaults(name: "first-launch")
    let completedKey = "airfloat.core-checks.firstLaunch.completed"
    let completedAtMsKey = "airfloat.core-checks.firstLaunch.completedAtMs"
    let completedVersionKey = "airfloat.core-checks.firstLaunch.completedVersion"
    let restDaysKey = "airfloat.core-checks.firstLaunch.restDays"
    let dateOverridesKey = "airfloat.core-checks.firstLaunch.dateOverrides"
    let scheduleRepository = ProgramScheduleRepository(
        defaults: defaults,
        restDaysKey: restDaysKey,
        dateOverridesKey: dateOverridesKey
    )
    let repository = FirstLaunchRepository(
        defaults: defaults,
        programScheduleRepository: scheduleRepository,
        completedKey: completedKey,
        completedAtMsKey: completedAtMsKey,
        completedVersionKey: completedVersionKey,
        currentOnboardingVersion: 2
    )

    let initialState = repository.loadState()
    try check(initialState.shouldShowFirstLaunch, "Empty first-launch repository should show onboarding")
    try checkEqual(initialState.completedAtMs, nil, "Empty first-launch state should not have completion timestamp")
    try checkEqual(initialState.completedVersion, 0, "Empty first-launch state should have version 0")

    repository.markCompleted()
    let completedState = repository.loadState()
    try check(!completedState.shouldShowFirstLaunch, "Completed current onboarding should not show first launch")
    try check(completedState.completedAtMs != nil, "Completion should persist completion timestamp")
    try checkEqual(completedState.completedVersion, 2, "Completion should persist current onboarding version")

    let upgradedRepository = FirstLaunchRepository(
        defaults: defaults,
        programScheduleRepository: scheduleRepository,
        completedKey: completedKey,
        completedAtMsKey: completedAtMsKey,
        completedVersionKey: completedVersionKey,
        currentOnboardingVersion: 3
    )
    try check(upgradedRepository.shouldShowFirstLaunch(), "Higher onboarding version should show first launch again")

    repository.completeWithWeeklyProgram(restDays: [.monday, .friday])
    try checkEqual(scheduleRepository.loadRestDays(), [.monday, .friday], "First launch completion should persist selected weekly rest days")
    try check(!repository.shouldShowFirstLaunch(), "Completing with weekly program should mark first launch complete")

    repository.resetForDebug()
    let resetState = repository.loadState()
    try check(resetState.shouldShowFirstLaunch, "Debug reset should show first launch again")
    try checkEqual(resetState.completedAtMs, nil, "Debug reset should clear completion timestamp")
    try checkEqual(resetState.completedVersion, 0, "Debug reset should clear completed version")
    try checkEqual(scheduleRepository.loadRestDays(), [.monday, .friday], "Debug reset should not erase selected schedule rest days")
}

func runTodayRecommendationInputChecks() throws {
    let calendar = utcCalendar()
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try utcDate(year: 2026, month: 5, day: 4, hour: 12)
    let restToday = ProgramSchedule(
        restDaysOfWeek: [],
        dateOverrides: [
            ProgramScheduleDate(date: now, calendar: calendar): .rest
        ]
    )

    let emptyInput = TodayRecommendationInput(
        sessions: [],
        schedule: restToday,
        calendar: calendar,
        now: now,
        timeZone: timeZone
    )
    let emptySummary = TodaySummaryFactory.build(input: emptyInput)
    let emptyZones = TodayBodyMapFactory.build(input: emptyInput)
    try check(emptySummary.isFirstSession, "Empty Today input should produce first-session summary")
    try checkEqual(emptySummary.recommendedExercise, .pressBarbell, "Empty Today recommendation should remain Barbell")
    try checkEqual(emptySummary.primaryActionTitle, "Start Barbell Press", "Empty Today primary action changed")
    try checkEqual(emptyZones.map(\.zone), [.chest, .core, .arms, .legs], "Today body map zone order changed")
    try check(emptyZones.allSatisfy { !$0.hasData }, "Empty Today body map should have no zone data")

    let olderBarbell = sampleSession(
        id: "today-input-older-barbell",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 2, hour: 9)),
        exerciseKey: .pressBarbell,
        goalReps: 10,
        completed: true,
        reps: 10,
        successfulAttempts: 10,
        failedAttempts: 0
    )
    let latestSquat = sampleSession(
        id: "today-input-latest-squat",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 4, hour: 9)),
        exerciseKey: .squatBeta,
        completed: true,
        reps: 8,
        successfulAttempts: 8,
        failedAttempts: 0
    )
    let sessionInput = TodayRecommendationInput(
        sessions: [olderBarbell, latestSquat],
        schedule: restToday,
        calendar: calendar,
        now: now,
        timeZone: timeZone
    )
    let summary = TodaySummaryFactory.build(input: sessionInput)
    let zones = TodayBodyMapFactory.build(input: sessionInput)
    try check(!summary.isFirstSession, "Today input with sessions should not produce first-session summary")
    try checkEqual(summary.recommendedExercise, .pressBarbell, "Today recommendation should stay Barbell until logic intentionally changes")
    try check(summary.latestSessionText.contains("Squats"), "Today input summary should use latest session text")
    try checkEqual(zones.first { $0.zone == .legs }?.precision, 100, "Today input body map should use Squat legs precision")
    try checkEqual(zones.first { $0.zone == .chest }?.lastSeenLabel, "2D AGO", "Today input body map should use deterministic now date")

    let trainToday = TodayRecommendationInput(
        sessions: [olderBarbell, latestSquat],
        schedule: ProgramSchedule(restDaysOfWeek: [], dateOverrides: [:]),
        calendar: calendar,
        now: now,
        timeZone: timeZone
    )
    try checkEqual(
        TodaySummaryFactory.build(input: sessionInput),
        TodaySummaryFactory.build(input: trainToday),
        "Today schedule input should not alter summary until recommendation logic uses schedule"
    )
    try checkEqual(
        TodayBodyMapFactory.build(input: sessionInput),
        TodayBodyMapFactory.build(input: trainToday),
        "Today schedule input should not alter body map until recommendation logic uses schedule"
    )
}

func runTrainRecentSessionsQualityChecks() throws {
    let calendar = utcCalendar()
    try checkEqual(
        TrainRecentSessionsFactory.build(sessions: [], calendar: calendar),
        [],
        "Empty Train recent sessions should render as empty"
    )

    let barbell = sampleSession(
        id: "recent-barbell",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 1, hour: 9)),
        exerciseKey: .pressBarbell,
        goalReps: 10,
        completed: true,
        reps: 10,
        successfulAttempts: 10,
        failedAttempts: 0
    )
    let dumbbell = sampleSession(
        id: "recent-dumbbell",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 2, hour: 9)),
        exerciseKey: .pressDumbbell,
        goalReps: 8,
        completed: false,
        reps: 6,
        successfulAttempts: 6,
        failedAttempts: 1
    )
    let squat = sampleSession(
        id: "recent-squat",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 3, hour: 9)),
        exerciseKey: .squatBeta,
        completed: true,
        reps: 12,
        successfulAttempts: 12,
        failedAttempts: 0
    )
    let pushupFallback = WorkoutSessionRecord(
        id: "recent-pushup-fallback",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 4, hour: 9)),
        exerciseKey: .pushup,
        presetKey: "legacy_unknown_pushup",
        goalReps: 20,
        completed: false,
        reps: 14,
        successfulAttempts: 14,
        failedAttempts: 2,
        durationMs: 30_000,
        estimatedKcal: 8.4,
        completionRate: 88,
        attempts: []
    )
    let situp = sampleSession(
        id: "recent-situp",
        timestampMs: timestampMs(try utcDate(year: 2026, month: 5, day: 5, hour: 9)),
        exerciseKey: .situp,
        goalReps: 15,
        completed: true,
        reps: 15,
        successfulAttempts: 15,
        failedAttempts: 0
    )

    let recent = TrainRecentSessionsFactory.build(
        sessions: [barbell, situp, dumbbell, pushupFallback, squat],
        calendar: calendar
    )
    try checkEqual(recent.count, 4, "Train recent sessions should cap output at four")
    try checkEqual(
        recent.map(\.id),
        ["recent-situp", "recent-pushup-fallback", "recent-squat", "recent-dumbbell"],
        "Train recent sessions should sort newest first and drop the fifth item"
    )
    try checkEqual(
        recent.map(\.title),
        ["Sit-up", "Push-up", "Squats", "Dumbbell Press"],
        "Train recent sessions should render titles across exercises"
    )
    try checkEqual(recent[0].meta, "05 MAY · 15 REPS", "Train recent Sit-up meta changed")
    try checkEqual(recent[1].meta, "04 MAY · 14 REPS", "Train recent fallback Push-up meta changed")
    try checkEqual(recent[2].meta, "03 MAY · 12 REPS", "Train recent Squat meta changed")
    try checkEqual(recent[3].meta, "02 MAY · 6 REPS", "Train recent partial Dumbbell meta changed")
}

func runAppNavigationContractChecks() throws {
    try checkEqual(AppRootNavigationContract.initialTab, .today, "App should open on Today after first-launch gate is cleared")
    try checkEqual(AppRootNavigationContract.firstLaunchCompletedTab, .today, "First launch completion should land on Today")
    try checkEqual(AppRootNavigationContract.liveSessionFinishedTab, .progress, "Live finish should land on Progress tab")
    try checkEqual(
        AppRootNavigationContract.tabAfterTodayOpenTrain(exerciseKey: .squatBeta),
        .train,
        "Today exercise action should open Train tab"
    )
    try checkEqual(
        AppRootNavigationContract.requestedTrainExerciseAfterTodayOpenTrain(exerciseKey: .squatBeta),
        .squatBeta,
        "Today exercise action should preserve requested Train exercise"
    )
    try checkEqual(
        AppRootNavigationContract.requestedTrainExerciseAfterTodayOpenTrain(exerciseKey: nil),
        nil,
        "Today open Train without exercise should preserve nil request"
    )
}

func runLiveDiagnosticsPolicyChecks() throws {
    try check(
        !LiveDiagnosticsPolicy.showsSquatDebugEventStrip,
        "Standalone core checks should compile without DEBUG and keep Squat debug event strip disabled"
    )
}

func squatPoseFrame(kneeAngleDeg: Double, confidence: Float = 1.0) -> LivePoseFrame {
    let radians = kneeAngleDeg * .pi / 180
    let ankleX = sin(radians)
    let ankleY = cos(radians)

    return LivePoseFrame(landmarks: [
        LivePoseLandmark(name: LivePoseLandmarkName.leftHip, x: -0.18, y: 1.0, confidence: confidence),
        LivePoseLandmark(name: LivePoseLandmarkName.leftKnee, x: -0.18, y: 0.0, confidence: confidence),
        LivePoseLandmark(name: LivePoseLandmarkName.leftAnkle, x: -0.18 + ankleX, y: ankleY, confidence: confidence),
        LivePoseLandmark(name: LivePoseLandmarkName.rightHip, x: 0.18, y: 1.0, confidence: confidence),
        LivePoseLandmark(name: LivePoseLandmarkName.rightKnee, x: 0.18, y: 0.0, confidence: confidence),
        LivePoseLandmark(name: LivePoseLandmarkName.rightAnkle, x: 0.18 + ankleX, y: ankleY, confidence: confidence)
    ])
}

func replaySquatAngles(
    _ angles: [Double],
    startMs: Int64 = 1_000,
    stepMs: Int64 = 100
) -> [LiveSquatCounterResult] {
    var counter = LiveSquatCounter()
    return angles.enumerated().map { offset, angle in
        counter.update(
            frame: squatPoseFrame(kneeAngleDeg: angle),
            timestampMs: startMs + Int64(offset) * stepMs
        )
    }
}

func pushupPoseFrame(
    elbowAngleDeg: Double,
    kneeAngleDeg: Double = 170,
    confidence: Float = 1.0
) -> LivePoseFrame {
    func jointTriplet(
        aName: String,
        bName: String,
        cName: String,
        originX: Double,
        originY: Double,
        angleDeg: Double
    ) -> [LivePoseLandmark] {
        let radians = angleDeg * .pi / 180
        return [
            LivePoseLandmark(name: aName, x: originX + 1.0, y: originY, confidence: confidence),
            LivePoseLandmark(name: bName, x: originX, y: originY, confidence: confidence),
            LivePoseLandmark(name: cName, x: originX + cos(radians), y: originY + sin(radians), confidence: confidence)
        ]
    }

    return LivePoseFrame(landmarks:
        jointTriplet(
            aName: LivePoseLandmarkName.leftShoulder,
            bName: LivePoseLandmarkName.leftElbow,
            cName: LivePoseLandmarkName.leftWrist,
            originX: -1.0,
            originY: 0,
            angleDeg: elbowAngleDeg
        ) +
        jointTriplet(
            aName: LivePoseLandmarkName.rightShoulder,
            bName: LivePoseLandmarkName.rightElbow,
            cName: LivePoseLandmarkName.rightWrist,
            originX: 1.0,
            originY: 0,
            angleDeg: elbowAngleDeg
        ) +
        jointTriplet(
            aName: LivePoseLandmarkName.leftHip,
            bName: LivePoseLandmarkName.leftKnee,
            cName: LivePoseLandmarkName.leftAnkle,
            originX: -1.0,
            originY: -1.2,
            angleDeg: kneeAngleDeg
        ) +
        jointTriplet(
            aName: LivePoseLandmarkName.rightHip,
            bName: LivePoseLandmarkName.rightKnee,
            cName: LivePoseLandmarkName.rightAnkle,
            originX: 1.0,
            originY: -1.2,
            angleDeg: kneeAngleDeg
        )
    )
}

func replayPushupAngles(
    _ angles: [Double],
    startMs: Int64 = 1_000,
    stepMs: Int64 = 100
) -> [LivePushupCounterResult] {
    var counter = LivePushupCounter()
    return angles.enumerated().map { offset, angle in
        counter.update(
            frame: pushupPoseFrame(elbowAngleDeg: angle),
            timestampMs: startMs + Int64(offset) * stepMs
        )
    }
}

func situpPoseFrame(
    hipAngleDeg: Double,
    confidence: Float = 1.0
) -> LivePoseFrame {
    func jointTriplet(
        aName: String,
        bName: String,
        cName: String,
        originX: Double,
        originY: Double,
        angleDeg: Double
    ) -> [LivePoseLandmark] {
        let radians = angleDeg * .pi / 180
        return [
            LivePoseLandmark(name: aName, x: originX + 1.0, y: originY, confidence: confidence),
            LivePoseLandmark(name: bName, x: originX, y: originY, confidence: confidence),
            LivePoseLandmark(name: cName, x: originX + cos(radians), y: originY + sin(radians), confidence: confidence)
        ]
    }

    return LivePoseFrame(landmarks:
        jointTriplet(
            aName: LivePoseLandmarkName.leftShoulder,
            bName: LivePoseLandmarkName.leftHip,
            cName: LivePoseLandmarkName.leftKnee,
            originX: -1.0,
            originY: 0,
            angleDeg: hipAngleDeg
        ) +
        jointTriplet(
            aName: LivePoseLandmarkName.rightShoulder,
            bName: LivePoseLandmarkName.rightHip,
            cName: LivePoseLandmarkName.rightKnee,
            originX: 1.0,
            originY: 0,
            angleDeg: hipAngleDeg
        )
    )
}

func replaySitupAngles(
    _ angles: [Double],
    startMs: Int64 = 1_000,
    stepMs: Int64 = 100
) -> [LiveSitupCounterResult] {
    var counter = LiveSitupCounter()
    return angles.enumerated().map { offset, angle in
        counter.update(
            frame: situpPoseFrame(hipAngleDeg: angle),
            timestampMs: startMs + Int64(offset) * stepMs
        )
    }
}

func runLiveSquatCounterReplayChecks() throws {
    let cleanRepResults = replaySquatAngles([
        158, 158, 154, 148, 140, 130, 118, 104, 92, 88, 96, 108, 122, 138, 154, 158
    ])
    let cleanTrace = cleanRepResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(cleanRepResults.last?.reps, 1, "Synthetic clean Squat replay should count one rep. Trace: \(cleanTrace)")
    try check(cleanRepResults.contains { $0.condition == .repCounted }, "Synthetic clean Squat replay should emit repCounted")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Cycle started") }, "Synthetic clean Squat replay should start a cycle")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Bottom reached") }, "Synthetic clean Squat replay should reach bottom")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Clean rep counted") }, "Synthetic clean Squat replay should emit clean rep event")

    let shallowResults = replaySquatAngles([
        158, 158, 154, 148, 140, 134, 130, 128, 126, 124, 126, 128, 132, 136, 146, 158
    ])
    try checkEqual(shallowResults.last?.reps, 0, "Synthetic shallow Squat replay should not count a rep")
    let shallowTrace = shallowResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try check(shallowResults.contains { $0.rejectReason == .insufficientTop }, "Synthetic shallow Squat replay should reject insufficient depth. Trace: \(shallowTrace)")

    var trackingGapCounter = LiveSquatCounter()
    _ = trackingGapCounter.update(frame: squatPoseFrame(kneeAngleDeg: 158), timestampMs: 1_000)
    let gap1 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_100)
    let gap2 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_200)
    let gap3 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_300)
    try checkEqual(gap1.condition, .badStart, "First Squat tracking gap should not immediately show trackingLost")
    try checkEqual(gap2.condition, .badStart, "Second Squat tracking gap should not immediately show trackingLost")
    try checkEqual(gap3.condition, .trackingLost, "Third Squat tracking gap should show trackingLost")
}

func runLivePushupCounterReplayChecks() throws {
    let cleanRepResults = replayPushupAngles([
        150, 150, 146, 140, 132, 122, 110, 96, 88, 96, 110, 124, 138, 148, 150
    ])
    let cleanTrace = cleanRepResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(cleanRepResults.last?.reps, 1, "Synthetic clean Push-up replay should count one rep. Trace: \(cleanTrace)")
    try check(cleanRepResults.contains { $0.condition == .repCounted }, "Synthetic clean Push-up replay should emit repCounted")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Cycle started") }, "Synthetic clean Push-up replay should start a cycle")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Bottom reached") }, "Synthetic clean Push-up replay should reach bottom")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Clean rep counted") }, "Synthetic clean Push-up replay should emit clean rep event")

    let shallowResults = replayPushupAngles([
        150, 150, 145, 138, 130, 124, 120, 118, 124, 132, 140, 148
    ])
    let shallowTrace = shallowResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(shallowResults.last?.reps, 0, "Synthetic shallow Push-up replay should not count a rep")
    try check(shallowResults.contains { $0.rejectReason == .insufficientTop }, "Synthetic shallow Push-up replay should reject insufficient depth. Trace: \(shallowTrace)")

    var trackingGapCounter = LivePushupCounter()
    _ = trackingGapCounter.update(frame: pushupPoseFrame(elbowAngleDeg: 150), timestampMs: 1_000)
    let gap1 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_100)
    let gap2 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_200)
    let gap3 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_300)
    try checkEqual(gap1.condition, .badStart, "First Push-up tracking gap should not immediately show trackingLost")
    try checkEqual(gap2.condition, .badStart, "Second Push-up tracking gap should not immediately show trackingLost")
    try checkEqual(gap3.condition, .trackingLost, "Third Push-up tracking gap should show trackingLost")
}

func runLiveSitupCounterReplayChecks() throws {
    let cleanRepResults = replaySitupAngles([
        170, 170, 166, 160, 152, 142, 130, 118, 104, 96, 104, 118, 132, 146, 160, 170, 170, 170, 170
    ])
    let cleanTrace = cleanRepResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(cleanRepResults.last?.reps, 1, "Synthetic clean Sit-up replay should count one rep. Trace: \(cleanTrace)")
    try check(cleanRepResults.contains { $0.condition == .repCounted }, "Synthetic clean Sit-up replay should emit repCounted")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Cycle started") }, "Synthetic clean Sit-up replay should start a cycle")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Bottom reached") }, "Synthetic clean Sit-up replay should reach bottom")
    try check(cleanRepResults.contains { $0.debugEvent.contains("Clean rep counted") }, "Synthetic clean Sit-up replay should emit clean rep event")

    let fastDropResults = replaySitupAngles([
        170, 170, 164, 154, 82, 54, 42, 58, 76, 96, 118, 138, 154, 168, 170, 170
    ])
    let fastDropTrace = fastDropResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(fastDropResults.last?.reps, 1, "Synthetic fast-drop Sit-up replay should count one rep. Trace: \(fastDropTrace)")
    try check(fastDropResults.contains { $0.debugEvent.contains("Cycle started") }, "Synthetic fast-drop Sit-up replay should start after a deep first drop")
    try check(fastDropResults.contains { $0.debugEvent.contains("Bottom reached") }, "Synthetic fast-drop Sit-up replay should reach bottom")

    let practicalReturnResults = replaySitupAngles([
        170, 170, 164, 154, 120, 96, 62, 34, 54, 76, 96, 108, 118, 126, 128, 130, 132, 134
    ])
    let practicalReturnTrace = practicalReturnResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(practicalReturnResults.last?.reps, 1, "Synthetic Sit-up replay should count when the return reaches the practical iOS top band. Trace: \(practicalReturnTrace)")
    try check(practicalReturnResults.contains { $0.debugEvent.contains("Clean rep counted") }, "Synthetic practical-return Sit-up replay should emit clean rep event")

    let oneSideLagResults = replaySitupAngles([
        170, 170, 160, 128, 112, 96, 84, 64, 92, 104, 118, 128, 132, 134, 138, 140
    ])
    let oneSideLagTrace = oneSideLagResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(oneSideLagResults.last?.reps, 1, "Synthetic Sit-up replay should not be blocked by early side-lag when final range is valid. Trace: \(oneSideLagTrace)")
    try check(!oneSideLagResults.contains { $0.debugEvent.contains("early left/right asymmetry") }, "Synthetic Sit-up replay should not use the old early asymmetry ignore path")

    let shallowResults = replaySitupAngles([
        160, 160, 156, 150, 142, 136, 132, 128, 128, 128, 132, 138, 146, 156, 160, 160, 160
    ])
    let shallowTrace = shallowResults.map { "\($0.reps):\($0.condition):\($0.debugEvent)" }.joined(separator: " | ")
    try checkEqual(shallowResults.last?.reps, 0, "Synthetic shallow Sit-up replay should not count a rep")
    try check(shallowResults.contains { $0.rejectReason == .insufficientTop }, "Synthetic shallow Sit-up replay should reject insufficient range. Trace: \(shallowTrace)")

    var trackingGapCounter = LiveSitupCounter()
    _ = trackingGapCounter.update(frame: situpPoseFrame(hipAngleDeg: 170), timestampMs: 1_000)
    let gap1 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_100)
    let gap2 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_200)
    let gap3 = trackingGapCounter.update(frame: LivePoseFrame(landmarks: []), timestampMs: 1_300)
    try checkEqual(gap1.condition, .badStart, "First Sit-up tracking gap should not immediately show trackingLost")
    try checkEqual(gap2.condition, .badStart, "Second Sit-up tracking gap should not immediately show trackingLost")
    try checkEqual(gap3.condition, .trackingLost, "Third Sit-up tracking gap should show trackingLost")
}

do {
    try runExerciseCatalogChecks()
    try runStartRequestChecks()
    try runTrainAvailabilityChecks()
    try runLiveExerciseTrackingPipelineChecks()
    try runSessionRepositoryChecks()
    try runLiveSessionStateChecks()
    try runProgressFactoryChecks()
    try runScheduleCalendarChecks()
    try runSquatExternalRenderingChecks()
    try runFirstLaunchRepositoryChecks()
    try runTodayRecommendationInputChecks()
    try runTrainRecentSessionsQualityChecks()
    try runAppNavigationContractChecks()
    try runLiveDiagnosticsPolicyChecks()
    try runLiveSquatCounterReplayChecks()
    try runLivePushupCounterReplayChecks()
    try runLiveSitupCounterReplayChecks()
    print("AirFloat core checks passed")
} catch {
    fputs("AirFloat core checks failed: \(error)\n", stderr)
    exit(1)
}
