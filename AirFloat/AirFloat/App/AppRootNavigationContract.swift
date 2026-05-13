import Foundation

enum AppRootTab: Hashable, Sendable {
    case today
    case train
    case progress
}

enum AppRootNavigationContract {
    static let initialTab: AppRootTab = .today
    static let firstLaunchCompletedTab: AppRootTab = .today
    static let liveSessionFinishedTab: AppRootTab = .progress

    static func tabAfterTodayOpenTrain(exerciseKey: ExerciseKey?) -> AppRootTab {
        .train
    }

    static func requestedTrainExerciseAfterTodayOpenTrain(exerciseKey: ExerciseKey?) -> ExerciseKey? {
        exerciseKey
    }
}
