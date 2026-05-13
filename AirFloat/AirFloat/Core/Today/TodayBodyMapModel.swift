import Foundation

enum MuscleZone: String, CaseIterable, Sendable {
    case chest
    case core
    case arms
    case legs

    var displayName: String {
        switch self {
        case .chest:
            return "CHEST"
        case .core:
            return "CORE"
        case .arms:
            return "SHOULDERS"
        case .legs:
            return "LEGS"
        }
    }
}

enum FormRank: String, Sendable {
    case raw = "RAW"
    case forming = "FORMING"
    case solid = "SOLID"
    case elite = "ELITE"
}

struct TodayZoneExerciseModel: Equatable, Sendable, Identifiable {
    var id: ExerciseKey { exerciseKey }

    let exerciseKey: ExerciseKey
    let presetKey: String
    let name: String
    let precision: Int
}

struct TodayMuscleZoneModel: Equatable, Sendable, Identifiable {
    var id: MuscleZone { zone }

    let zone: MuscleZone
    let precision: Int
    let rank: FormRank
    let lastSeenLabel: String
    let exercises: [TodayZoneExerciseModel]
    let missReason: String?

    var hasData: Bool {
        lastSeenLabel != "—" || exercises.contains { $0.precision > 0 }
    }
}
