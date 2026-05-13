import Foundation

struct WorkoutSessionRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let timestampMs: Int64
    let exerciseKey: ExerciseKey
    let presetKey: String
    let goalReps: Int
    let completed: Bool
    let reps: Int
    let successfulAttempts: Int
    let failedAttempts: Int
    let durationMs: Int64
    let estimatedKcal: Double
    let completionRate: Int
    let attempts: [WorkoutSessionAttemptRecord]
}
