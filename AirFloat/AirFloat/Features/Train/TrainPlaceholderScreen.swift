import SwiftUI

struct TrainPlaceholderScreen: View {
    private let sessionRepository = SessionRepository()
    let requestedExerciseKey: ExerciseKey?
    let onSessionFinished: () -> Void

    @State private var selectedExercise = ExerciseCatalog.defaultExercise
    @State private var goalReps = 0
    @State private var recentSessions: [TrainRecentSessionModel] = []
    @State private var recentSessionsError: String?
    @State private var isShowingExerciseChooser = false

    init(
        requestedExerciseKey: ExerciseKey? = nil,
        onSessionFinished: @escaping () -> Void = {}
    ) {
        self.requestedExerciseKey = requestedExerciseKey
        self.onSessionFinished = onSessionFinished
    }

    private var canStartSelectedExercise: Bool {
        availability(for: selectedExercise).canStart
    }

    private var startButtonTitle: String {
        availability(for: selectedExercise).startButtonTitle
    }

    private var launchGoalReps: Int {
        selectedExercise.goalRepsEnabled ? goalReps : 0
    }

    private var startRequest: WorkoutSessionStartRequest {
        WorkoutSessionStartRequest(
            exercise: selectedExercise,
            goalReps: launchGoalReps
        )
    }

    var body: some View {
        ShellScreenScaffold(
            title: "Train",
            subtitle: "Choose a movement and start the current iOS training path."
        ) {
            VStack(spacing: 16) {
                selectedExerciseHero
                selectedExerciseControl
                goalRepsControl

                NavigationLink {
                    LivePlaceholderScreen(
                        startRequest: startRequest,
                        onSessionFinished: onSessionFinished
                    )
                } label: {
                    Label(startButtonTitle, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartSelectedExercise)

                recentSessionsSection
            }
        }
        .navigationTitle("Train")
        .sheet(isPresented: $isShowingExerciseChooser) {
            exerciseChooserSheet
        }
        .onAppear {
            applyRequestedExercise()
            loadRecentSessions()
        }
        .onChange(of: requestedExerciseKey) {
            applyRequestedExercise()
        }
    }

    private var selectedExerciseHero: some View {
        ZStack(alignment: .bottomLeading) {
            if let artworkAssetName = selectedExercise.artworkAssetName {
                Image(artworkAssetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.tertiarySystemGroupedBackground)
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.58),
                    .black.opacity(0.08),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedExercise.shortLabel)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))

                Text(selectedExercise.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, -16)
    }

    private var selectedExerciseControl: some View {
        Button {
            isShowingExerciseChooser = true
        } label: {
            HStack(spacing: 14) {
                Text(selectedExercise.shortLabel)
                    .font(.headline.monospaced())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected movement")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectedExercise.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var goalRepsControl: some View {
        let isEnabled = selectedExercise.goalRepsEnabled
        let valueText = isEnabled ? goalRepsValueText : "N/A"

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("REPS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(valueText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
            }

            Spacer()

            Button {
                adjustGoalReps(direction: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
            .disabled(!isEnabled)
            .accessibilityLabel("Decrease reps goal")

            Button {
                adjustGoalReps(direction: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
            .disabled(!isEnabled)
            .accessibilityLabel("Increase reps goal")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var goalRepsValueText: String {
        goalReps > 0 ? "\(goalReps)" : "FREE"
    }

    private var exerciseChooserSheet: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCatalog.all) { exercise in
                    exerciseOptionRow(for: exercise)
                }
            }
            .navigationTitle("Choose Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingExerciseChooser = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent sessions")
                    .font(.headline)

                Spacer()

                Text(recentSessionsHeaderValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let recentSessionsError {
                Text(recentSessionsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No recent sessions")
                        .font(.subheadline.weight(.semibold))

                    Text("Finish a workout and it will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentSessions) { session in
                        recentSessionRow(session)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var recentSessionsHeaderValue: String {
        recentSessions.isEmpty ? "NO HISTORY" : "\(recentSessions.count) READY"
    }

    private func recentSessionRow(_ session: TrainRecentSessionModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(session.meta)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private func exerciseOptionRow(for exercise: ExerciseCatalogItem) -> some View {
        let isSelected = exercise.key == selectedExercise.key
        let availability = availability(for: exercise)
        let isAvailable = availability.canStart

        return Button {
            guard isAvailable else { return }
            selectedExercise = exercise
            isShowingExerciseChooser = false
        } label: {
            HStack(spacing: 14) {
                Text(exercise.shortLabel)
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundStyle(isAvailable ? .white : .secondary)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isAvailable ? Color.accentColor : Color(.tertiarySystemFill))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.headline)
                        .foregroundStyle(isAvailable ? .primary : .secondary)

                    Text(availability.rowLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else if !isAvailable {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private func adjustGoalReps(direction: Int) {
        guard selectedExercise.goalRepsEnabled else {
            goalReps = 0
            return
        }

        if direction > 0, goalReps <= 0 {
            goalReps = 10
            return
        }

        let nextValue = goalReps + (direction * 5)
        goalReps = min(99, max(0, nextValue))
    }

    private func loadRecentSessions() {
        do {
            let sessions = try sessionRepository.loadSessions()
            recentSessions = TrainRecentSessionsFactory.build(sessions: sessions)
            recentSessionsError = nil
        } catch {
            recentSessions = []
            recentSessionsError = "Recent sessions failed to load: \(error.localizedDescription)"
        }
    }

    private func applyRequestedExercise() {
        guard let requestedExerciseKey else {
            return
        }

        selectedExercise = ExerciseCatalog.item(for: requestedExerciseKey)
        if !selectedExercise.goalRepsEnabled {
            goalReps = 0
        }
    }

    private func availability(for exercise: ExerciseCatalogItem) -> TrainExerciseAvailability {
        TrainExerciseAvailability.availability(for: exercise)
    }
}
