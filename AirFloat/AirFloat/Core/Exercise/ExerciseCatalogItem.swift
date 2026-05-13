import Foundation

struct ExerciseCatalogItem: Equatable, Identifiable, Sendable {
    var id: ExerciseKey { key }

    let key: ExerciseKey
    let presetKey: String
    let displayName: String
    let shortLabel: String
    let progressTabLabel: String
    let goalRepsEnabled: Bool
    let artworkAssetName: String?
}
