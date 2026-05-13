import Foundation

enum ExerciseKey: String, Codable, Sendable {
    case pressBarbell = "press_barbell"
    case pressDumbbell = "press_dumbbell"
    case pushup
    case situp
    case squatBeta = "squat_beta"

    var displayName: String {
        switch self {
        case .pressBarbell:
            return "Barbell Press"
        case .pressDumbbell:
            return "Dumbbell Press"
        case .pushup:
            return "Push-up"
        case .situp:
            return "Sit-up"
        case .squatBeta:
            return "Squats"
        }
    }
}
