import SwiftUI

struct FirstLaunchGatePlaceholderScreen: View {
    let complete: (Set<ProgramWeekday>) -> Void

    @State private var currentStep = 0
    @State private var selectedRestDays: Set<ProgramWeekday>

    init(
        initialRestDays: Set<ProgramWeekday>,
        complete: @escaping (Set<ProgramWeekday>) -> Void
    ) {
        self.complete = complete
        _selectedRestDays = State(initialValue: initialRestDays)
    }

    var body: some View {
        ShellScreenScaffold(
            title: "First Launch",
            subtitle: "Step \(currentStep + 1) / 3"
        ) {
            VStack(spacing: 16) {
                stepCard

                if currentStep == 2 {
                    restDayPicker
                }

                controls
            }
        }
    }

    private var stepCard: some View {
        VStack(spacing: 10) {
            Text(stepLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(stepTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(stepBody)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(featureTitle)
                    .font(.headline)

                Text(featureBody)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var restDayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly rest days")
                .font(.headline)

            Text("Tap the days you usually rest.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(ProgramWeekday.allCases, id: \.self) { weekday in
                    restDayButton(weekday)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button {
                    currentStep = max(0, currentStep - 1)
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if currentStep < 2 {
                    currentStep += 1
                } else {
                    complete(selectedRestDays)
                }
            } label: {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func restDayButton(_ weekday: ProgramWeekday) -> some View {
        let isSelected = selectedRestDays.contains(weekday)

        return Button {
            if isSelected {
                selectedRestDays.remove(weekday)
            } else {
                selectedRestDays.insert(weekday)
            }
        } label: {
            Text(weekday.shortLabel)
                .font(.caption.weight(.bold).monospaced())
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(weekday.shortLabel) rest day")
    }

    private var stepLabel: String {
        switch currentStep {
        case 0:
            return "WELCOME TO AIRFLOAT"
        case 1:
            return "AIRFLOAT LOOP"
        default:
            return "BASE PROGRAM"
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case 0:
            return "Know the next move"
        case 1:
            return "Today -> Train -> Live -> Progress"
        default:
            return "Set your week"
        }
    }

    private var stepBody: String {
        switch currentStep {
        case 0:
            return "AirFloat gives you a clear daily loop: what to train, how to start, how to perform, and what to review next."
        case 1:
            return "The app is designed as one ritual instead of disconnected screens."
        default:
            return "Choose your weekly rest days. You can still fine-tune individual dates later in Progress."
        }
    }

    private var featureTitle: String {
        switch currentStep {
        case 0:
            return "Why it works"
        case 1:
            return "The training loop"
        default:
            return "Rest shapes the calendar"
        }
    }

    private var featureBody: String {
        switch currentStep {
        case 0:
            return "Today points you in, Train prepares the session, Live tracks the set, and Progress closes the feedback loop."
        case 1:
            return "Today sets focus. Train launches the session. Live records the work. Progress shows what changed."
        default:
            return "AirFloat uses this weekly template as the base program before date-specific overrides are added."
        }
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case 0:
            return "Next"
        case 1:
            return "Set My Week"
        default:
            return "Enter AirFloat"
        }
    }
}
