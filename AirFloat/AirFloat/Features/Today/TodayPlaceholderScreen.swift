import SwiftUI

struct TodayPlaceholderScreen: View {
    private let sessionRepository = SessionRepository()
    let openTrain: (ExerciseKey?) -> Void

    @State private var summary = TodaySummaryFactory.build(sessions: [])
    @State private var zones = TodayBodyMapFactory.build(sessions: [])
    @State private var selectedZone: MuscleZone = .chest
    @State private var readError: String?

    init(openTrain: @escaping (ExerciseKey?) -> Void = { _ in }) {
        self.openTrain = openTrain
    }

    var body: some View {
        ShellScreenScaffold(
            title: "Today",
            subtitle: "Chest, core, shoulders, legs",
            showsHeader: false
        ) {
            VStack(spacing: 18) {
                todayHeader
                TodayZoneCarousel(
                    selectedZone: $selectedZone,
                    zones: zones
                )
                selectedZoneDetail
            }
        }
        .onAppear {
            loadSummary()
        }
    }

    private var todayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("TODAY")
                .font(.system(size: 42, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(dateMonthLabel)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 1, height: 18)

                Text(dateDayLabel)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityLabel("\(dateMonthLabel) \(dateDayLabel)")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var selectedZoneDetail: some View {
        if let zone = zones.first(where: { $0.zone == selectedZone }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(zone.zone.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(zone.accentColor)
                        .lineLimit(1)

                    Spacer()

                    Text(zone.rank.rawValue)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(zone.badgeTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(zone.accentColor.opacity(zone.hasData ? 0.22 : 0.14))
                        )
                }

                HStack(spacing: 10) {
                    ProgressView(value: Double(zone.precision), total: 100)
                        .tint(zone.accentColor)

                    Text(zone.hasData ? "\(zone.precision)%" : "—")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(zone.hasData ? Color.primary : Color.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Text(zone.hasData ? "\(zone.exercises.count) EXERCISES · \(zone.lastSeenLabel)" : "ZONE NOT MAPPED YET")
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if let missReason = zone.missReason {
                    Text(missReason)
                        .font(.caption.monospaced())
                        .foregroundStyle(zone.accentColor)
                        .textCase(.uppercase)
                }

                VStack(spacing: 8) {
                    ForEach(zone.exercises) { exercise in
                        TodayExerciseRow(exercise: exercise, accentColor: zone.accentColor)
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        openTrain(zone.primaryExerciseKey)
                    } label: {
                        Label(zone.actionTitle.uppercased(), systemImage: "figure.strengthtraining.traditional")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(zone.accentColor)

                    Text(zone.actionFootnote)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func loadSummary() {
        do {
            let sessions = try sessionRepository.loadSessions()
            summary = TodaySummaryFactory.build(sessions: sessions)
            zones = TodayBodyMapFactory.build(sessions: sessions)
            readError = nil
            if !zones.contains(where: { $0.zone == selectedZone }) {
                selectedZone = zones.first?.zone ?? .chest
            }
        } catch {
            summary = TodaySummaryFactory.build(sessions: [])
            zones = TodayBodyMapFactory.build(sessions: [])
            readError = "Today state read failed: \(error.localizedDescription)"
        }
    }

    private var dateMonthLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: Date()).uppercased()
    }

    private var dateDayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d"
        return formatter.string(from: Date())
    }
}

private struct TodayExerciseRow: View {
    let exercise: TodayZoneExerciseModel
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: 7, height: 7)

            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(exercise.precision > 0 ? "\(exercise.precision)%" : "—")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(exercise.availabilityLabel)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(exercise.isReady ? accentColor : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(exercise.isReady ? accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                    )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}

extension TodayMuscleZoneModel {
    var accentColor: Color {
        guard hasData else {
            return .secondary
        }

        switch rank {
        case .elite:
            return .yellow
        case .solid:
            return .green
        case .forming:
            return .orange
        case .raw:
            return .red
        }
    }

    var actionTitle: String {
        guard let primaryExercise else {
            return "Open Train"
        }

        if primaryExercise.canStart {
            return hasData ? "Launch \(primaryExercise.name)" : "Start \(primaryExercise.name)"
        }

        return "View \(primaryExercise.name)"
    }

    var actionFootnote: String {
        guard let primaryExercise else {
            return "Choose a movement in Train."
        }

        if primaryExercise.availability == .betaValidation {
            return "Beta validation in Train."
        }

        return primaryExercise.canStart
            ? "Ready in Train."
            : "\(primaryExercise.name) will be selected in Train. Tracking for this movement is coming later."
    }

    var badgeTextColor: Color {
        hasData ? accentColor : .secondary
    }

    var primaryExercise: TodayZoneExerciseModel? {
        exercises.max {
            if $0.precision == $1.precision {
                return $0.name > $1.name
            }

            return $0.precision < $1.precision
        } ?? exercises.first
    }

    var primaryExerciseKey: ExerciseKey? {
        primaryExercise?.exerciseKey
    }
}

private extension TodayZoneExerciseModel {
    var availability: TrainExerciseAvailability {
        TrainExerciseAvailability.availability(for: exerciseKey)
    }

    var canStart: Bool {
        availability.canStart
    }

    var isReady: Bool {
        canStart
    }

    var availabilityLabel: String {
        availability.rowLabel.uppercased()
    }
}
