import Foundation

struct WorkoutSessionStartRequest: Equatable, Sendable {
    let exercise: ExerciseCatalogItem
    let goalReps: Int

    var goalDisplayText: String {
        if goalReps > 0 {
            return "Goal: \(goalReps) reps"
        }

        return "Goal: Free session"
    }

    static var defaultBarbellPress: WorkoutSessionStartRequest {
        WorkoutSessionStartRequest(
            exercise: ExerciseCatalog.defaultExercise,
            goalReps: 0
        )
    }
}
