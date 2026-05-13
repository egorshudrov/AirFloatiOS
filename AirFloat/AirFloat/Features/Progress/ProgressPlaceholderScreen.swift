import SwiftUI

struct ProgressPlaceholderScreen: View {
    private let sessionRepository = SessionRepository()
    private let scheduleRepository = ProgramScheduleRepository()

    @State private var sessions: [WorkoutSessionRecord] = []
    @State private var selectedExercise = ExerciseCatalog.defaultExercise
    @State private var latestMap: LatestSessionMapModel?
    @State private var selectedAttemptIndex = -1
    @State private var selectedCalendarDayID: Int64?
    @State private var displayedCalendarMonth = Calendar.current.dateComponents([.year, .month], from: Date())
    @State private var summary = ProgressSummaryFactory.build(sessions: [])
    @State private var calendarMonth = ConsistencyCalendarFactory.buildCurrentMonth(sessions: [])
    @State private var readError: String?

    var body: some View {
        ShellScreenScaffold(
            title: "Progress",
            subtitle: "Latest-session readback is connected for the first vertical slice."
        ) {
            VStack(spacing: 16) {
                progressSummary(summary)

                exerciseSelector

                if let latestMap {
                    latestSessionMap(latestMap)
                } else {
                    emptyState(for: selectedExercise)
                }

                consistencyCalendar(calendarMonth)
            }
        }
        .navigationTitle("Progress")
        .onAppear {
            loadLatestSession()
        }
        .onChange(of: selectedExercise.key) {
            refreshLatestMap()
        }
    }

    private func progressSummary(_ summary: ProgressSummaryModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                summaryTile(summary.sessionCountText)
                summaryTile(summary.repCountText)
            }

            Text(summary.attemptBalanceText)
                .font(.callout.weight(.semibold))

            Text(summary.latestSessionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func summaryTile(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
    }

    private var exerciseSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExerciseCatalog.all) { exercise in
                    Button {
                        selectedExercise = exercise
                    } label: {
                        Text(exercise.progressTabLabel)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .foregroundStyle(exercise.key == selectedExercise.key ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(exercise.key == selectedExercise.key ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityLabel("Exercise selector")
    }

    private func emptyState(for exercise: ExerciseCatalogItem) -> some View {
        VStack(spacing: 10) {
            Text("Latest session map")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(emptyStateTitle(for: exercise))
                .font(.title3.weight(.semibold))

            Text(emptyStateMessage(for: exercise))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func latestSessionMap(_ map: LatestSessionMapModel) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Latest session map")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(map.sessionTitle)
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Text(map.sessionStatus)
                                .font(.caption2.monospaced().weight(.black))
                                .foregroundStyle(sessionStatusTextColor(map.sessionStatus))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(sessionStatusColor(map.sessionStatus))
                                )
                        }

                        Text(map.sessionMeta)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    ProgressScoreRing(score: scoreValue(from: map.sessionBadge))
                }
            }

            ProgressAttemptsChart(
                attempts: map.attempts,
                selectedIndex: $selectedAttemptIndex
            )

            attemptDetail(selectedAttemptDetail(for: map))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func attemptDetail(_ detail: LatestAttemptDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.title)
                    .font(.title3.weight(.bold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Spacer()

                Text(detail.badge)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(attemptBadgeTextColor(detail.tone))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(toneColor(detail.tone))
                    )
            }

            Text(detail.meta)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail.detail)
                .font(.callout)
                .foregroundStyle(attemptDetailTextColor(detail.tone))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private func consistencyCalendar(_ month: ConsistencyCalendarMonthModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Consistency")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(month.monthTitle)
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Text(month.adherenceText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("\(month.summaryText) - \(month.streakText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    calendarMonthButton(systemImage: "chevron.left") {
                        shiftCalendarMonth(by: -1)
                    }

                    Text(month.monthTitle)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)

                    calendarMonthButton(systemImage: "chevron.right") {
                        shiftCalendarMonth(by: 1)
                    }
                }
                .padding(.top, 4)
            }

            HStack(spacing: 6) {
                ForEach(month.weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(0..<month.leadingEmptyDays, id: \.self) { index in
                    Color.clear
                        .frame(height: 38)
                        .accessibilityHidden(true)
                        .id("empty-\(index)")
                }

                ForEach(month.days) { day in
                    calendarDayCell(day)
                }
            }

            if let selectedDay = selectedCalendarDay(in: month) {
                calendarDayDetail(selectedDay)
            }

            HStack(spacing: 10) {
                legendItem("Trained", color: .green)
                legendItem("Missed", color: .red)
                legendItem("Rest", color: .purple)
                legendItem("Today", color: .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func calendarDayCell(_ day: ConsistencyCalendarDayModel) -> some View {
        let isSelected = selectedCalendarDayID == day.id

        return Button {
            selectedCalendarDayID = isSelected ? nil : day.id
        } label: {
            Text("\(day.dayNumber)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(calendarTextColor(day.state))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(calendarFillColor(day.state))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(calendarCellStrokeColor(day, isSelected: isSelected), lineWidth: isSelected ? 2 : calendarCellStrokeWidth(day))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendarAccessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func calendarDayDetail(_ day: ConsistencyCalendarDayModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(calendarDetailDate(day))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                Text(calendarDetailBadge(day))
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(calendarDetailAccent(day))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(calendarDetailAccent(day).opacity(0.14))
                    )
            }

            if day.sessions.isEmpty {
                Text(calendarDetailEmptyText(day))
                    .font(.callout)
                    .foregroundStyle(calendarDetailAccent(day))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(day.sessions.enumerated()), id: \.offset) { _, session in
                        calendarSessionRow(session, accent: calendarDetailAccent(day))
                    }
                }
            }

            calendarOverrideControls(day)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(calendarDetailAccent(day).opacity(0.35), lineWidth: 1)
        )
    }

    private func calendarOverrideControls(_ day: ConsistencyCalendarDayModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                calendarOverrideButton(
                    title: "TRAIN DAY",
                    isActive: calendarPlannedDayType(day) == .train,
                    accent: .green
                ) {
                    setCalendarDateOverride(day, type: .train)
                }

                calendarOverrideButton(
                    title: "REST DAY",
                    isActive: calendarPlannedDayType(day) == .rest,
                    accent: .purple
                ) {
                    setCalendarDateOverride(day, type: .rest)
                }

                if calendarHasDateOverride(day) {
                    calendarOverrideButton(
                        title: "CLEAR",
                        isActive: false,
                        accent: .secondary
                    ) {
                        clearCalendarDateOverride(day)
                    }
                }
            }

            Text(calendarHasDateOverride(day) ? "Manual override is active for this date." : "This date follows your weekly template.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func calendarOverrideButton(
        title: String,
        isActive: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(isActive ? Color.white : accent)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .background(
                    Capsule()
                        .fill(isActive ? accent : accent.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(accent.opacity(isActive ? 0 : 0.36), lineWidth: isActive ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func calendarSessionRow(_ session: CalendarDaySessionModel, accent: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)

            Text(session.exerciseName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 10)

            Text("\(session.reps) REPS · \(session.completionRate)%")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 7, height: 7)

            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func calendarMonthButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 28)
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func calendarAccessibilityLabel(_ day: ConsistencyCalendarDayModel) -> String {
        let stateText: String
        switch day.state {
        case .trainedPerfect, .trainedHigh, .trainedMid, .trainedLow:
            stateText = "trained, \(day.sessions.count) sessions, \(day.averageScore) percent average"
        case .plannedRest:
            stateText = "planned rest"
        case .missed:
            stateText = "missed"
        case .rest:
            stateText = "rest"
        case .future:
            stateText = "future"
        case .todayEmpty:
            stateText = "today, no session yet"
        }

        return "Day \(day.dayNumber), \(stateText)"
    }

    private func calendarFillColor(_ state: CalendarDayState) -> Color {
        switch state {
        case .trainedPerfect:
            return .green
        case .trainedHigh:
            return .green.opacity(0.62)
        case .trainedMid:
            return .green.opacity(0.32)
        case .trainedLow:
            return .green.opacity(0.16)
        case .plannedRest:
            return .purple.opacity(0.12)
        case .missed:
            return .red.opacity(0.14)
        case .rest, .todayEmpty:
            return Color(.tertiarySystemGroupedBackground)
        case .future:
            return Color(.tertiarySystemGroupedBackground).opacity(0.45)
        }
    }

    private func calendarStrokeColor(_ state: CalendarDayState) -> Color {
        switch state {
        case .trainedLow:
            return .green.opacity(0.35)
        case .plannedRest:
            return .purple.opacity(0.35)
        case .missed:
            return .red.opacity(0.35)
        case .todayEmpty:
            return .primary.opacity(0.35)
        default:
            return .clear
        }
    }

    private func calendarCellStrokeColor(_ day: ConsistencyCalendarDayModel, isSelected: Bool) -> Color {
        isSelected ? calendarDetailAccent(day) : calendarStrokeColor(day.state)
    }

    private func calendarCellStrokeWidth(_ day: ConsistencyCalendarDayModel) -> CGFloat {
        calendarStrokeColor(day.state) == .clear ? 0 : 1
    }

    private func calendarTextColor(_ state: CalendarDayState) -> Color {
        switch state {
        case .trainedPerfect, .trainedHigh:
            return .white
        case .trainedMid, .trainedLow:
            return .green
        case .plannedRest:
            return .purple
        case .missed:
            return .red
        case .rest:
            return .secondary
        case .future:
            return .secondary.opacity(0.45)
        case .todayEmpty:
            return .primary
        }
    }

    private func selectedCalendarDay(in month: ConsistencyCalendarMonthModel) -> ConsistencyCalendarDayModel? {
        guard let selectedCalendarDayID else {
            return nil
        }

        return month.days.first { $0.id == selectedCalendarDayID }
    }

    private func calendarDetailDate(_ day: ConsistencyCalendarDayModel) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        let date = Date(timeIntervalSince1970: TimeInterval(day.startOfDayMs) / 1000.0)
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    private func calendarDetailBadge(_ day: ConsistencyCalendarDayModel) -> String {
        switch day.state {
        case .trainedPerfect, .trainedHigh, .trainedMid, .trainedLow:
            return "WORKOUT"
        case .missed:
            return "MISSED"
        case .plannedRest:
            return "REST"
        case .todayEmpty:
            return "TODAY"
        case .future:
            return "FUTURE"
        case .rest:
            return "REST"
        }
    }

    private func calendarDetailEmptyText(_ day: ConsistencyCalendarDayModel) -> String {
        switch day.state {
        case .missed:
            return "A workout was expected here, but no session was saved."
        case .plannedRest:
            return "This day is marked as planned rest."
        case .todayEmpty:
            return "No completed workout yet today."
        case .future:
            return "This day is still ahead."
        case .rest:
            return "No workout data for this day."
        case .trainedPerfect, .trainedHigh, .trainedMid, .trainedLow:
            return "No workout data for this day."
        }
    }

    private func calendarDetailAccent(_ day: ConsistencyCalendarDayModel) -> Color {
        switch day.state {
        case .trainedPerfect, .trainedHigh, .trainedMid, .trainedLow:
            return .green
        case .missed:
            return .red
        case .plannedRest:
            return .purple
        case .todayEmpty:
            return .primary
        case .future:
            return .secondary
        case .rest:
            return .secondary
        }
    }

    private func calendarDate(_ day: ConsistencyCalendarDayModel) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.startOfDayMs) / 1000.0)
    }

    private func programScheduleDate(_ day: ConsistencyCalendarDayModel) -> ProgramScheduleDate {
        ProgramScheduleDate(date: calendarDate(day))
    }

    private func calendarHasDateOverride(_ day: ConsistencyCalendarDayModel) -> Bool {
        scheduleRepository.loadDateOverrides()[programScheduleDate(day)] != nil
    }

    private func calendarPlannedDayType(_ day: ConsistencyCalendarDayModel) -> PlannedDayType {
        scheduleRepository.loadSchedule().plannedDayType(for: calendarDate(day))
    }

    private func loadLatestSession() {
        do {
            let sessions = try sessionRepository.loadSessions()
            let schedule = scheduleRepository.loadSchedule()
            self.sessions = sessions
            summary = ProgressSummaryFactory.build(sessions: sessions)
            displayedCalendarMonth = Calendar.current.dateComponents([.year, .month], from: Date())
            calendarMonth = buildDisplayedCalendarMonth(sessions: sessions, schedule: schedule)
            readError = nil

            if let session = sessions.first {
                selectedExercise = ExerciseCatalog.item(for: session.exerciseKey)
            } else {
                selectedExercise = ExerciseCatalog.defaultExercise
            }

            refreshLatestMap()
        } catch {
            sessions = []
            latestMap = nil
            readError = "Latest session read failed: \(error.localizedDescription)"
        }
    }

    private func shiftCalendarMonth(by offset: Int) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        let year = displayedCalendarMonth.year ?? calendar.component(.year, from: Date())
        let month = displayedCalendarMonth.month ?? calendar.component(.month, from: Date())
        let currentDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let nextDate = calendar.date(byAdding: .month, value: offset, to: currentDate) ?? currentDate
        displayedCalendarMonth = calendar.dateComponents([.year, .month], from: nextDate)

        let schedule = scheduleRepository.loadSchedule()
        calendarMonth = buildDisplayedCalendarMonth(sessions: sessions, schedule: schedule)
        selectedCalendarDayID = nil
    }

    private func setCalendarDateOverride(_ day: ConsistencyCalendarDayModel, type: PlannedDayType) {
        scheduleRepository.setDateOverride(
            date: programScheduleDate(day),
            type: type
        )
        rebuildDisplayedCalendarMonth(preservingSelection: day.id)
    }

    private func clearCalendarDateOverride(_ day: ConsistencyCalendarDayModel) {
        scheduleRepository.clearDateOverride(date: programScheduleDate(day))
        rebuildDisplayedCalendarMonth(preservingSelection: day.id)
    }

    private func rebuildDisplayedCalendarMonth(preservingSelection selectedDayID: Int64?) {
        let schedule = scheduleRepository.loadSchedule()
        calendarMonth = buildDisplayedCalendarMonth(sessions: sessions, schedule: schedule)
        selectedCalendarDayID = selectedDayID
    }

    private func buildDisplayedCalendarMonth(
        sessions: [WorkoutSessionRecord],
        schedule: ProgramSchedule
    ) -> ConsistencyCalendarMonthModel {
        let year = displayedCalendarMonth.year ?? Calendar.current.component(.year, from: Date())
        let month = displayedCalendarMonth.month ?? Calendar.current.component(.month, from: Date())

        return ConsistencyCalendarFactory.buildMonth(
            year: year,
            month: month,
            sessions: sessions,
            schedule: schedule
        )
    }

    private func refreshLatestMap() {
        guard readError == nil else {
            latestMap = nil
            return
        }

        guard let session = sessions.first(where: { $0.exerciseKey == selectedExercise.key }) else {
            latestMap = nil
            selectedAttemptIndex = -1
            return
        }

        let nextMap = LatestSessionMapFactory.build(session: session)
        latestMap = nextMap
        selectedAttemptIndex = nextMap.selectedIndex
    }

    private func emptyStateTitle(for exercise: ExerciseCatalogItem) -> String {
        if readError != nil {
            return "Progress unavailable"
        }

        if sessions.isEmpty {
            return "No saved session yet"
        }

        return "No \(exercise.displayName) session yet"
    }

    private func emptyStateMessage(for exercise: ExerciseCatalogItem) -> String {
        if let readError {
            return readError
        }

        if sessions.isEmpty {
            return "Finish a Live session to save the first vertical-slice workout and render the latest-session map here."
        }

        if TrainExerciseAvailability.availability(for: exercise).canStart {
            return "Finish a Live session to save the first \(exercise.displayName) workout."
        }

        return "When this exercise is supported in Train, its latest session map will appear here."
    }

    private func toneColor(_ tone: LatestAttemptTone) -> Color {
        switch tone {
        case .clean:
            return .green
        case .miss:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func attemptBadgeTextColor(_ tone: LatestAttemptTone) -> Color {
        switch tone {
        case .clean, .neutral:
            return .black
        case .miss:
            return .white
        }
    }

    private func attemptDetailTextColor(_ tone: LatestAttemptTone) -> Color {
        switch tone {
        case .clean:
            return .primary
        case .miss:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func sessionStatusColor(_ status: String) -> Color {
        status == "COMPLETE" ? Color.green : Color.yellow.opacity(0.26)
    }

    private func sessionStatusTextColor(_ status: String) -> Color {
        status == "COMPLETE" ? Color.black : Color.primary
    }

    private func scoreValue(from badge: String) -> Int {
        Int(badge.filter(\.isNumber)) ?? 0
    }

    private func selectedAttemptDetail(for map: LatestSessionMapModel) -> LatestAttemptDetailModel {
        guard map.attempts.indices.contains(selectedAttemptIndex) else {
            return map.selectedAttempt
        }

        return LatestSessionMapFactory.detail(
            for: map.attempts[selectedAttemptIndex],
            isLegacy: map.isLegacy
        )
    }
}

private struct ProgressAttemptsChart: View {
    let attempts: [WorkoutSessionAttemptRecord]
    @Binding var selectedIndex: Int

    private let chartHeight: CGFloat = 190

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let content = CGRect(
                x: 12,
                y: 20,
                width: max(1, size.width - 24),
                height: max(1, size.height - 44)
            )
            let plotLeft = content.minX + 44
            let plotRight = content.maxX
            let cleanY = content.minY + content.height * 0.28
            let missY = content.minY + content.height * 0.74
            let points = chartPoints(
                plotLeft: plotLeft,
                plotRight: plotRight,
                cleanY: cleanY,
                missY: missY
            )

            ZStack(alignment: .topLeading) {
                if attempts.isEmpty {
                    Text("NO REP TELEMETRY FOR THIS SESSION")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: size.width, height: size.height)
                } else {
                    laneLabel("CLEAN", x: content.minX, y: cleanY)
                    laneLabel("MISS", x: content.minX, y: missY)

                    dashedLane(from: CGPoint(x: plotLeft, y: cleanY), to: CGPoint(x: plotRight, y: cleanY))
                    dashedLane(from: CGPoint(x: plotLeft, y: missY), to: CGPoint(x: plotRight, y: missY))

                    connectorPath(points)
                        .stroke(Color.secondary.opacity(0.26), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                    connectorPath(points)
                        .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if points.indices.contains(selectedIndex) {
                        Path { path in
                            let selectedPoint = points[selectedIndex]
                            path.move(to: CGPoint(x: selectedPoint.x, y: content.minY))
                            path.addLine(to: selectedPoint)
                        }
                        .stroke(Color.yellow.opacity(0.45), lineWidth: 1.5)
                    }

                    ForEach(Array(attempts.enumerated()), id: \.offset) { offset, attempt in
                        attemptPoint(attempt: attempt, isSelected: offset == selectedIndex) {
                            selectedIndex = offset
                        }
                        .position(points[offset])
                    }

                    bottomLabel(attempts.first?.index ?? 1, x: points.first?.x ?? plotLeft, y: content.maxY + 18)
                    if attempts.count > 2, points.indices.contains(selectedIndex) {
                        bottomLabel(attempts[selectedIndex].index, x: points[selectedIndex].x, y: content.maxY + 18)
                    }
                    if attempts.count > 1 {
                        bottomLabel(attempts.last?.index ?? attempts.count, x: points.last?.x ?? plotRight, y: content.maxY + 18)
                    }
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityElement(children: .contain)
    }

    private func chartPoints(
        plotLeft: CGFloat,
        plotRight: CGFloat,
        cleanY: CGFloat,
        missY: CGFloat
    ) -> [CGPoint] {
        attempts.enumerated().map { offset, attempt in
            let x: CGFloat
            if attempts.count <= 1 {
                x = plotLeft
            } else {
                let step = (plotRight - plotLeft) / CGFloat(attempts.count - 1)
                x = plotLeft + step * CGFloat(offset)
            }

            return CGPoint(x: x, y: attempt.success ? cleanY : missY)
        }
    }

    private func connectorPath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else {
                return
            }

            path.move(to: first)
            points.dropFirst().forEach { point in
                path.addLine(to: point)
            }
        }
    }

    private func dashedLane(from start: CGPoint, to end: CGPoint) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }

    private func laneLabel(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .position(x: x + 20, y: y)
    }

    private func bottomLabel(_ value: Int, x: CGFloat, y: CGFloat) -> some View {
        Text("\(value)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .position(x: x, y: y)
    }

    private func attemptPoint(
        attempt: WorkoutSessionAttemptRecord,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tone = attempt.success ? Color.green : Color.red

        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(tone.opacity(isSelected ? 0.32 : 0.16))
                    .frame(width: isSelected ? 34 : 30, height: isSelected ? 34 : 30)

                Circle()
                    .fill(tone)
                    .frame(width: isSelected ? 20 : 16, height: isSelected ? 20 : 16)

                if isSelected {
                    Circle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attempt \(attempt.index), \(attempt.success ? "clean" : "miss")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ProgressScoreRing: View {
    let score: Int

    private var clampedScore: Int {
        min(100, max(0, score))
    }

    private var progress: Double {
        Double(clampedScore) / 100.0
    }

    private var toneColor: Color {
        switch clampedScore {
        case ...60:
            return .red
        case ...85:
            return .orange
        default:
            return .green
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 9)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    toneColor,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: toneColor.opacity(0.26), radius: 8)

            VStack(spacing: 1) {
                Text("\(clampedScore)")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(toneColor)

                Text("CLEAN RATE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 82, height: 82)
        .accessibilityLabel("Clean rate \(clampedScore) percent")
    }
}
