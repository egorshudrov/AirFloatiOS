import Foundation

enum ExerciseCatalog {
    static let all: [ExerciseCatalogItem] = [
        ExerciseCatalogItem(
            key: .pressBarbell,
            presetKey: ExerciseKey.pressBarbell.rawValue,
            displayName: ExerciseKey.pressBarbell.displayName,
            shortLabel: "BB",
            progressTabLabel: "BARBELL",
            goalRepsEnabled: true,
            artworkAssetName: "train_barbell_press"
        ),
        ExerciseCatalogItem(
            key: .pressDumbbell,
            presetKey: ExerciseKey.pressDumbbell.rawValue,
            displayName: ExerciseKey.pressDumbbell.displayName,
            shortLabel: "DB",
            progressTabLabel: "DUMBBELL",
            goalRepsEnabled: true,
            artworkAssetName: "train_dumbbell_press"
        ),
        ExerciseCatalogItem(
            key: .squatBeta,
            presetKey: ExerciseKey.squatBeta.rawValue,
            displayName: ExerciseKey.squatBeta.displayName,
            shortLabel: "SQ",
            progressTabLabel: "SQUATS",
            goalRepsEnabled: false,
            artworkAssetName: "train_squats"
        ),
        ExerciseCatalogItem(
            key: .pushup,
            presetKey: ExerciseKey.pushup.rawValue,
            displayName: ExerciseKey.pushup.displayName,
            shortLabel: "PU",
            progressTabLabel: "PUSH-UP",
            goalRepsEnabled: true,
            artworkAssetName: "train_pushups"
        ),
        ExerciseCatalogItem(
            key: .situp,
            presetKey: ExerciseKey.situp.rawValue,
            displayName: ExerciseKey.situp.displayName,
            shortLabel: "SU",
            progressTabLabel: "SIT-UP",
            goalRepsEnabled: true,
            artworkAssetName: "train_sit_up"
        )
    ]

    static var defaultExercise: ExerciseCatalogItem {
        item(for: .pressBarbell)
    }

    static func item(for key: ExerciseKey) -> ExerciseCatalogItem {
        all.first { $0.key == key } ?? all[0]
    }

    static func item(forPresetKey presetKey: String) -> ExerciseCatalogItem? {
        all.first { $0.presetKey == presetKey }
    }
}
