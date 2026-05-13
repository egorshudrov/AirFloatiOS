import Foundation

struct FirstLaunchState: Equatable, Sendable {
    let shouldShowFirstLaunch: Bool
    let completedAtMs: Int64?
    let completedVersion: Int
}
