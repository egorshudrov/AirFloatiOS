import Foundation

struct TodaySummaryModel: Equatable, Sendable {
    let isFirstSession: Bool
    let headline: String
    let subheadline: String
    let recommendedExercise: ExerciseKey
    let primaryActionTitle: String
    let sessionCountText: String
    let latestSessionText: String
}
