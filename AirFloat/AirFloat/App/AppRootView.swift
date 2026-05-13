import SwiftUI

struct AppRootView: View {
    private let firstLaunchRepository = FirstLaunchRepository()
    private let programScheduleRepository = ProgramScheduleRepository()

    @State private var selectedTab: AppRootTab = AppRootNavigationContract.initialTab
    @State private var shouldShowFirstLaunch = true
    @State private var requestedTrainExerciseKey: ExerciseKey?

    var body: some View {
        Group {
            if shouldShowFirstLaunch {
                FirstLaunchGatePlaceholderScreen(
                    initialRestDays: programScheduleRepository.loadRestDays()
                ) { restDays in
                    completeFirstLaunch(restDays: restDays)
                }
            } else {
                rootTabs
            }
        }
        .onAppear {
            shouldShowFirstLaunch = firstLaunchRepository.shouldShowFirstLaunch()
        }
    }

    private var rootTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayPlaceholderScreen { exerciseKey in
                    requestedTrainExerciseKey = AppRootNavigationContract.requestedTrainExerciseAfterTodayOpenTrain(
                        exerciseKey: exerciseKey
                    )
                    selectedTab = AppRootNavigationContract.tabAfterTodayOpenTrain(exerciseKey: exerciseKey)
                }
            }
            .tabItem {
                Label("Today", systemImage: "house.fill")
            }
            .tag(AppRootTab.today)

            NavigationStack {
                TrainPlaceholderScreen(requestedExerciseKey: requestedTrainExerciseKey) {
                    selectedTab = AppRootNavigationContract.liveSessionFinishedTab
                }
            }
            .tabItem {
                Label("Train", systemImage: "figure.strengthtraining.traditional")
            }
            .tag(AppRootTab.train)

            NavigationStack {
                ProgressPlaceholderScreen()
            }
            .tabItem {
                Label("Progress", systemImage: "chart.bar.fill")
            }
            .tag(AppRootTab.progress)
        }
    }

    private func completeFirstLaunch(restDays: Set<ProgramWeekday>) {
        firstLaunchRepository.completeWithWeeklyProgram(restDays: restDays)
        selectedTab = AppRootNavigationContract.firstLaunchCompletedTab
        shouldShowFirstLaunch = false
    }
}
