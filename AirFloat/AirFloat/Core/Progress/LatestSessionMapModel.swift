import Foundation

enum LatestAttemptTone: String, Codable, Equatable, Sendable {
    case clean
    case miss
    case neutral
}

struct LatestAttemptDetailModel: Codable, Equatable, Sendable {
    let title: String
    let badge: String
    let tone: LatestAttemptTone
    let meta: String
    let detail: String
}

struct LatestSessionMapModel: Codable, Equatable, Sendable {
    let sessionTitle: String
    let sessionBadge: String
    let sessionMeta: String
    let sessionStatus: String
    let attempts: [WorkoutSessionAttemptRecord]
    let selectedIndex: Int
    let selectedAttempt: LatestAttemptDetailModel
    let isLegacy: Bool
}
