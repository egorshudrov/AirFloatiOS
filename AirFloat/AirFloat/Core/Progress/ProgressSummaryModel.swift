import Foundation

struct ProgressSummaryModel: Equatable, Sendable {
    let title: String
    let sessionCountText: String
    let repCountText: String
    let attemptBalanceText: String
    let latestSessionText: String
}
