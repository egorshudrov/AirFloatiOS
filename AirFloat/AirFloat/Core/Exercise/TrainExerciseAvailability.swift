import Foundation

enum TrainExerciseAvailability: String, Codable, Equatable, Sendable {
    case ready
    case betaValidation
    case planned

    var canStart: Bool {
        self != .planned
    }

    var rowLabel: String {
        switch self {
        case .ready:
            return "Ready"
        case .betaValidation:
            return "Beta validation"
        case .planned:
            return "Planned"
        }
    }

    var startButtonTitle: String {
        switch self {
        case .ready:
            return "Start Session"
        case .betaValidation:
            return "Start Beta Session"
        case .planned:
            return "Start Session"
        }
    }

    static func availability(for exercise: ExerciseCatalogItem) -> TrainExerciseAvailability {
        availability(for: exercise.key)
    }

    static func availability(for key: ExerciseKey) -> TrainExerciseAvailability {
        switch key {
        case .pressBarbell, .pressDumbbell:
            return .ready
        case .squatBeta:
            return .betaValidation
        case .pushup:
            return .betaValidation
        case .situp:
            return .betaValidation
        }
    }
}

enum LiveExerciseTrackingPipeline: Equatable, Sendable {
    case barbellPressCounter
    case squatCounter
    case pushupCounter
    case situpCounter
    case unavailable

    static func pipeline(for key: ExerciseKey) -> LiveExerciseTrackingPipeline {
        switch key {
        case .pressBarbell, .pressDumbbell:
            return .barbellPressCounter
        case .squatBeta:
            return .squatCounter
        case .pushup:
            return .pushupCounter
        case .situp:
            return .situpCounter
        }
    }
}
