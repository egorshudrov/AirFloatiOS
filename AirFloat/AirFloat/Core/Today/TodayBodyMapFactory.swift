import Foundation

enum TodayBodyMapFactory {
    static func build(input: TodayRecommendationInput) -> [TodayMuscleZoneModel] {
        build(
            sessions: input.sessions,
            calendar: input.calendar,
            now: input.now
        )
    }

    static func build(
        sessions: [WorkoutSessionRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [TodayMuscleZoneModel] {
        let normalizedCalendar = calendar
        let today = normalizedCalendar.startOfDay(for: now)
        let precisionByExercise = buildExercisePrecisionMap(sessions: sessions)
        let lastSeenByExercise = buildExerciseLastSeenMap(
            sessions: sessions,
            calendar: normalizedCalendar,
            today: today
        )

        return zoneDefinitions.map { definition in
            let precision = averagePrecision(
                exerciseKeys: definition.exerciseKeys,
                precisionByExercise: precisionByExercise
            )
            let lastSeenLabel = mostRecentLabel(
                exerciseKeys: definition.exerciseKeys,
                lastSeenByExercise: lastSeenByExercise
            )
            let exercises = definition.exerciseKeys.map { exerciseKey in
                let item = ExerciseCatalog.item(for: exerciseKey)
                return TodayZoneExerciseModel(
                    exerciseKey: exerciseKey,
                    presetKey: item.presetKey,
                    name: item.displayName,
                    precision: precisionByExercise[exerciseKey, default: 0]
                )
            }

            return TodayMuscleZoneModel(
                zone: definition.zone,
                precision: precision,
                rank: rank(for: precision),
                lastSeenLabel: lastSeenLabel,
                exercises: exercises,
                missReason: missReason(
                    zone: definition.zone,
                    precision: precision,
                    hasZoneData: lastSeenLabel != "—"
                )
            )
        }
    }

    private struct ZoneDefinition {
        let zone: MuscleZone
        let exerciseKeys: [ExerciseKey]
    }

    private static let zoneDefinitions: [ZoneDefinition] = [
        ZoneDefinition(zone: .chest, exerciseKeys: [.pressBarbell, .pressDumbbell, .pushup]),
        ZoneDefinition(zone: .core, exerciseKeys: [.situp]),
        ZoneDefinition(zone: .arms, exerciseKeys: [.pressDumbbell]),
        ZoneDefinition(zone: .legs, exerciseKeys: [.squatBeta])
    ]

    private static func buildExercisePrecisionMap(
        sessions: [WorkoutSessionRecord]
    ) -> [ExerciseKey: Int] {
        Dictionary(uniqueKeysWithValues: ExerciseCatalog.all.map { item in
            let latestSession = sessions
                .filter { $0.exerciseKey == item.key }
                .max { $0.timestampMs < $1.timestampMs }
            return (item.key, latestSession?.completionRate ?? 0)
        })
    }

    private static func buildExerciseLastSeenMap(
        sessions: [WorkoutSessionRecord],
        calendar: Calendar,
        today: Date
    ) -> [ExerciseKey: String] {
        Dictionary(uniqueKeysWithValues: ExerciseCatalog.all.map { item in
            let latestSession = sessions
                .filter { $0.exerciseKey == item.key }
                .max { $0.timestampMs < $1.timestampMs }

            guard let latestSession else {
                return (item.key, "—")
            }

            let sessionDay = calendar.startOfDay(
                for: Date(timeIntervalSince1970: TimeInterval(latestSession.timestampMs) / 1000.0)
            )
            let days = calendar.dateComponents([.day], from: sessionDay, to: today).day ?? 0
            return (item.key, "\(max(0, days))D AGO")
        })
    }

    private static func averagePrecision(
        exerciseKeys: [ExerciseKey],
        precisionByExercise: [ExerciseKey: Int]
    ) -> Int {
        let values = exerciseKeys.compactMap { key -> Int? in
            let precision = precisionByExercise[key, default: 0]
            return precision > 0 ? precision : nil
        }

        guard !values.isEmpty else {
            return 0
        }

        let average = Double(values.reduce(0, +)) / Double(values.count)
        return Int(average.rounded())
    }

    private static func mostRecentLabel(
        exerciseKeys: [ExerciseKey],
        lastSeenByExercise: [ExerciseKey: String]
    ) -> String {
        let labels = exerciseKeys
            .compactMap { lastSeenByExercise[$0] }
            .filter { $0 != "—" }

        return labels.min { daysAgo(from: $0) < daysAgo(from: $1) } ?? "—"
    }

    private static func daysAgo(from label: String) -> Int {
        Int(label.split(separator: "D").first ?? "") ?? Int.max
    }

    private static func rank(for precision: Int) -> FormRank {
        switch precision {
        case 89...100:
            return .elite
        case 76...88:
            return .solid
        case 61...75:
            return .forming
        default:
            return .raw
        }
    }

    private static func missReason(
        zone: MuscleZone,
        precision: Int,
        hasZoneData: Bool
    ) -> String? {
        guard hasZoneData, precision <= 75 else {
            return nil
        }

        switch zone {
        case .chest:
            return "FORM BREAK — press path opened on the final reps"
        case .core:
            return "FORM BREAK — trunk control opened too early"
        case .arms:
            return "FORM BREAK — shoulder drive drifted unevenly"
        case .legs:
            return "FORM BREAK — left knee tracking inward"
        }
    }
}
