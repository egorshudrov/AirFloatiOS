import Foundation

struct WorkoutSessionAttemptRecord: Codable, Equatable, Sendable, Identifiable {
    let index: Int
    let repSnapshot: Int
    let success: Bool
    let elapsedMs: Int64
    let estimatedKcal: Double
    let detail: String

    var id: Int { index }
}
