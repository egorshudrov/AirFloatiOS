import SwiftUI

struct LivePlaceholderScreen: View {
    @StateObject private var cameraController = LiveCameraController()
    private let sessionRepository = SessionRepository()
    private let startRequest: WorkoutSessionStartRequest
    private let onSessionFinished: () -> Void

    @State private var liveSessionState = LiveSessionState()
    @State private var finishError: String?
    @State private var lastRecordedRejectEventID: Int?
    @State private var lastRecordedSquatRejectEventID: Int?
    @State private var lastRecordedPushupRejectEventID: Int?
    @State private var lastRecordedSitupRejectEventID: Int?
    @State private var isShowingLiveInstructions = true
    @State private var isSessionFinished = false

    init(
        startRequest: WorkoutSessionStartRequest = .defaultBarbellPress,
        onSessionFinished: @escaping () -> Void = {}
    ) {
        self.startRequest = startRequest
        self.onSessionFinished = onSessionFinished
    }

    var body: some View {
        liveSessionSurface
        .navigationTitle("Live")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            liveSessionState.startIfNeeded(at: Int64(Date().timeIntervalSince1970 * 1000))
            cameraController.handleAppear(exerciseKey: startRequest.exercise.key)
        }
        .onChange(of: cameraController.barbellPressState.reps) { _, reps in
            guard liveTrackingPipeline == .barbellPressCounter else { return }
            recordCleanRepsIfNeeded(reps)
            finishIfGoalReached(reps: reps)
        }
        .onChange(of: cameraController.barbellPressState.rejectEventID) { _, _ in
            guard liveTrackingPipeline == .barbellPressCounter else { return }
            recordRejectedRepIfNeeded(cameraController.barbellPressState)
        }
        .onChange(of: cameraController.squatState.reps) { _, reps in
            guard startRequest.exercise.key == .squatBeta else { return }
            recordSquatCleanRepsIfNeeded(reps)
            finishIfGoalReached(reps: reps)
        }
        .onChange(of: cameraController.squatState.rejectEventID) { _, _ in
            guard startRequest.exercise.key == .squatBeta else { return }
            recordSquatRejectedRepIfNeeded(cameraController.squatState)
        }
        .onChange(of: cameraController.pushupState.reps) { _, reps in
            guard liveTrackingPipeline == .pushupCounter else { return }
            recordPushupCleanRepsIfNeeded(reps)
            finishIfGoalReached(reps: reps)
        }
        .onChange(of: cameraController.pushupState.rejectEventID) { _, _ in
            guard liveTrackingPipeline == .pushupCounter else { return }
            recordPushupRejectedRepIfNeeded(cameraController.pushupState)
        }
        .onChange(of: cameraController.situpState.reps) { _, reps in
            guard liveTrackingPipeline == .situpCounter else { return }
            recordSitupCleanRepsIfNeeded(reps)
            finishIfGoalReached(reps: reps)
        }
        .onChange(of: cameraController.situpState.rejectEventID) { _, _ in
            guard liveTrackingPipeline == .situpCounter else { return }
            recordSitupRejectedRepIfNeeded(cameraController.situpState)
        }
        .onDisappear {
            cameraController.handleDisappear()
        }
    }

    private var liveSessionSurface: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            cameraLayer
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.78), .clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LiveSkeletonOverlay(frame: cameraController.latestPoseFrame)
                .opacity(cameraController.latestPoseFrame == nil ? 0 : 1)
                .ignoresSafeArea()

            VStack {
                topLiveHeader

                Spacer()

                repCounterCluster

                Spacer()

                bottomLiveControls
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)

            if isShowingLiveInstructions {
                liveInstructionOverlay
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var cameraLayer: some View {
        switch cameraController.state {
        case .ready:
            LiveCameraPreviewView(session: cameraController.session)
        case .idle:
            cameraStateCard(
                title: "Preparing camera",
                message: "The live preview baseline will request access when needed.",
                showsProgress: true
            )
        case .requestingPermission:
            cameraStateCard(
                title: "Requesting camera access",
                message: "Allow camera permission to mount the native live preview.",
                showsProgress: true
            )
        case .permissionDenied:
            cameraStateCard(
                title: "Camera access denied",
                message: "Enable camera access in Settings, then return to Live and retry.",
                symbolName: "camera.fill.badge.xmark"
            )
        case .restricted:
            cameraStateCard(
                title: "Camera access restricted",
                message: "This device currently blocks camera access for the app.",
                symbolName: "lock.slash"
            )
        case .frontCameraUnavailable:
            cameraStateCard(
                title: "Front camera unavailable",
                message: "Use a real iPhone for live preview validation.",
                symbolName: "iphone.slash"
            )
        case let .failed(message):
            cameraStateCard(
                title: "Camera preview failed",
                message: message,
                symbolName: "exclamationmark.triangle.fill"
            )
        }
    }

    private var topLiveHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(startRequest.exercise.displayName.uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(startRequest.goalDisplayText.uppercased()) · \(liveCounterTitle)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(MediaPipePoseModelResource.isBundled ? "MEDIAPIPE LIVE" : "MODEL MISSING")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(MediaPipePoseModelResource.isBundled ? Color.green : Color.red)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    isShowingLiveInstructions.toggle()
                }
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.52), in: Circle())
            }
            .accessibilityLabel("Live instructions")

            VStack(spacing: 6) {
                Text(liveGaugeTitle)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))

                Text("\(Int((liveCounterProgress * 100).rounded()))%")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 78)
            .padding(.vertical, 10)
            .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var liveInstructionOverlay: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(startRequest.exercise.displayName.uppercased()) LIVE")
                            .font(.title3.monospaced().weight(.black))
                            .foregroundStyle(.white)

                        Text(liveInstructionIntro)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            isShowingLiveInstructions = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: Circle())
                    }
                    .accessibilityLabel("Hide live instructions")
                }

                VStack(spacing: 9) {
                    ForEach(liveInstructionSteps, id: \.index) { step in
                        instructionStep(index: step.index, title: step.title, detail: step.detail)
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        isShowingLiveInstructions = false
                    }
                } label: {
                    Text("START LIVE")
                        .font(.headline.monospaced().weight(.black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(16)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.green.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.52), radius: 22, x: 0, y: 14)
            .padding(.horizontal, 18)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func instructionStep(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(Color.green)
                .frame(width: 34, height: 30)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.monospaced().weight(.black))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var repCounterCluster: some View {
        VStack(spacing: 2) {
            Text("REPS")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.white.opacity(0.64))

            Text("\(liveCounterReps)")
                .font(.system(size: 108, weight: .black, design: .monospaced))
                .minimumScaleFactor(0.55)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 18, x: 0, y: 6)

            if shouldShowTopTempoCue {
                Text("DO IT SLOWLY")
                    .font(.caption.monospaced().weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Text(liveCounterDetail)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
                .frame(maxWidth: 300)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var shouldShowTopTempoCue: Bool {
        guard liveTrackingPipeline == .barbellPressCounter else { return false }
        return cameraController.barbellPressState.condition == .tracking &&
            cameraController.barbellPressState.progress >= 0.86
    }

    private var bottomLiveControls: some View {
        VStack(spacing: 12) {
            if let finishError {
                Text(finishError)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 10) {
                conditionPill

                Spacer()

                Button {
                    finishSession(completed: startRequest.goalReps == 0 && liveSessionState.reps > 0)
                } label: {
                    Text("FINISH")
                        .font(.headline.weight(.bold))
                        .frame(width: 136, height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSessionFinished)
            }

            diagnosticsStrip

            if startRequest.exercise.key == .squatBeta,
               LiveDiagnosticsPolicy.showsSquatDebugEventStrip
            {
                squatDebugEventStrip
            }

            if startRequest.exercise.key == .situp,
               LiveDiagnosticsPolicy.showsSquatDebugEventStrip
            {
                situpDebugEventStrip
            }
        }
    }

    private var conditionPill: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cameraController.poseRuntimeState.title.uppercased())
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.white)

            Text(cameraController.poseDiagnostics.summary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var diagnosticsStrip: some View {
        HStack(spacing: 6) {
            ForEach(liveDiagnosticLandmarks, id: \.label) { landmark in
                diagnosticChip(landmark)
            }
        }
    }

    private var liveDiagnosticLandmarks: [LivePoseDiagnosticLandmark] {
        switch liveTrackingPipeline {
        case .situpCounter:
            return [
                cameraController.poseDiagnostics.leftShoulder,
                cameraController.poseDiagnostics.leftHip,
                cameraController.poseDiagnostics.leftKnee,
                cameraController.poseDiagnostics.rightShoulder,
                cameraController.poseDiagnostics.rightHip,
                cameraController.poseDiagnostics.rightKnee
            ]
        case .squatCounter:
            return [
                cameraController.poseDiagnostics.leftHip,
                cameraController.poseDiagnostics.leftKnee,
                cameraController.poseDiagnostics.rightHip,
                cameraController.poseDiagnostics.rightKnee
            ]
        case .barbellPressCounter, .pushupCounter, .unavailable:
            return [
                cameraController.poseDiagnostics.leftShoulder,
                cameraController.poseDiagnostics.leftElbow,
                cameraController.poseDiagnostics.leftWrist,
                cameraController.poseDiagnostics.rightShoulder,
                cameraController.poseDiagnostics.rightElbow,
                cameraController.poseDiagnostics.rightWrist
            ]
        }
    }

    private func diagnosticChip(_ landmark: LivePoseDiagnosticLandmark) -> some View {
        Text(landmark.confidenceText)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(landmark.isVisible ? Color.green : Color.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var squatDebugEventStrip: some View {
        Text(cameraController.squatState.debugEvent)
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var situpDebugEventStrip: some View {
        Text(cameraController.situpState.debugEvent)
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var poseRuntimeCard: some View {
        VStack(spacing: 8) {
            Text("Pose runtime")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(cameraController.poseRuntimeState.title)
                .font(.headline)

            Text(cameraController.poseRuntimeState.detail)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var barbellRuntimeCard: some View {
        VStack(spacing: 8) {
            Text("Barbell runtime")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(liveCounterTitle)
                .font(.headline)

            Text(liveCounterDetail)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var poseDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pose diagnostics")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(cameraController.poseDiagnostics.summary)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                diagnosticCell(cameraController.poseDiagnostics.leftShoulder)
                diagnosticCell(cameraController.poseDiagnostics.leftElbow)
                diagnosticCell(cameraController.poseDiagnostics.leftWrist)
                diagnosticCell(cameraController.poseDiagnostics.rightShoulder)
                diagnosticCell(cameraController.poseDiagnostics.rightElbow)
                diagnosticCell(cameraController.poseDiagnostics.rightWrist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func diagnosticCell(_ landmark: LivePoseDiagnosticLandmark) -> some View {
        VStack(spacing: 4) {
            Text(landmark.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(landmark.confidenceText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(landmark.isVisible ? .green : .red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(landmark.isVisible ? Color.green.opacity(0.12) : Color.red.opacity(0.10))
        )
    }

    private var cameraSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black)

            switch cameraController.state {
            case .ready:
                LiveCameraPreviewView(session: cameraController.session)
            case .idle:
                cameraStateCard(
                    title: "Preparing camera",
                    message: "The live preview baseline will request access when needed.",
                    showsProgress: true
                )
            case .requestingPermission:
                cameraStateCard(
                    title: "Requesting camera access",
                    message: "Allow camera permission to mount the native live preview.",
                    showsProgress: true
                )
            case .permissionDenied:
                cameraStateCard(
                    title: "Camera access denied",
                    message: "Enable camera access in Settings, then return to Live and retry.",
                    symbolName: "camera.fill.badge.xmark"
                )
            case .restricted:
                cameraStateCard(
                    title: "Camera access restricted",
                    message: "This device currently blocks camera access for the app.",
                    symbolName: "lock.slash"
                )
            case .frontCameraUnavailable:
                cameraStateCard(
                    title: "Front camera unavailable",
                    message: "This baseline expects a front camera. The simulator cannot provide it here, so use a real iPhone for live preview validation.",
                    symbolName: "iphone.slash"
                )
            case let .failed(message):
                cameraStateCard(
                    title: "Camera preview failed",
                    message: message,
                    symbolName: "exclamationmark.triangle.fill"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .bottom) {
            if cameraController.state.canRetry {
                Button("Retry Camera Setup") {
                    cameraController.refreshAuthorizationAndStartIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .padding(20)
            }
        }
    }

    private func cameraStateCard(
        title: String,
        message: String,
        symbolName: String? = nil,
        showsProgress: Bool = false
    ) -> some View {
        VStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .tint(.white)
            } else if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(24)
    }

    private func finishIfGoalReached(reps: Int) {
        guard startRequest.goalReps > 0, reps >= startRequest.goalReps else { return }
        finishSession(completed: true)
    }

    private func finishSession(completed: Bool) {
        guard !isSessionFinished else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let session = buildSession(completed: completed, nowMs: nowMs)
        guard let session else {
            finishError = "No tracked reps yet. Complete one rep or use Back to leave Live."
            return
        }

        do {
            isSessionFinished = true
            try sessionRepository.save(session)
            finishError = nil
            onSessionFinished()
        } catch {
            isSessionFinished = false
            finishError = "Session save failed: \(error.localizedDescription)"
        }
    }

    private func recordCleanRepsIfNeeded(_ reps: Int) {
        liveSessionState.recordCleanRepIfNeeded(
            reps: reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000),
            detail: liveFallbackCleanDetail
        )
    }

    private func recordRejectedRepIfNeeded(_ state: LiveBarbellPressCounterResult) {
        guard let rejectEventID = state.rejectEventID,
              rejectEventID != lastRecordedRejectEventID,
              let rejectReason = state.rejectReason
        else {
            return
        }

        lastRecordedRejectEventID = rejectEventID
        liveSessionState.recordRejectedRep(
            reason: rejectReason,
            repSnapshot: state.reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func recordSquatCleanRepsIfNeeded(_ reps: Int) {
        liveSessionState.recordCleanRepIfNeeded(
            reps: reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000),
            detail: "Live MediaPipe Squat clean rep counted from camera tracking."
        )
    }

    private func recordSquatRejectedRepIfNeeded(_ state: LiveSquatCounterResult) {
        guard let rejectEventID = state.rejectEventID,
              rejectEventID != lastRecordedSquatRejectEventID,
              let rejectReason = state.rejectReason,
              rejectReason != .trackingLost
        else {
            return
        }

        lastRecordedSquatRejectEventID = rejectEventID
        liveSessionState.recordRejectedAttempt(
            detail: rejectReason.missedAttemptDetail,
            repSnapshot: state.reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func recordPushupCleanRepsIfNeeded(_ reps: Int) {
        liveSessionState.recordCleanRepIfNeeded(
            reps: reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000),
            detail: "Live MediaPipe Push-up clean rep counted from camera tracking."
        )
    }

    private func recordPushupRejectedRepIfNeeded(_ state: LivePushupCounterResult) {
        guard let rejectEventID = state.rejectEventID,
              rejectEventID != lastRecordedPushupRejectEventID,
              let rejectReason = state.rejectReason
        else {
            return
        }

        lastRecordedPushupRejectEventID = rejectEventID
        liveSessionState.recordRejectedAttempt(
            detail: rejectReason.missedAttemptDetail,
            repSnapshot: state.reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func recordSitupCleanRepsIfNeeded(_ reps: Int) {
        liveSessionState.recordCleanRepIfNeeded(
            reps: reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000),
            detail: "Live MediaPipe Sit-up clean rep counted from camera tracking."
        )
    }

    private func recordSitupRejectedRepIfNeeded(_ state: LiveSitupCounterResult) {
        guard let rejectEventID = state.rejectEventID,
              rejectEventID != lastRecordedSitupRejectEventID,
              let rejectReason = state.rejectReason
        else {
            return
        }

        lastRecordedSitupRejectEventID = rejectEventID
        liveSessionState.recordRejectedAttempt(
            detail: rejectReason.missedAttemptDetail,
            repSnapshot: state.reps,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func buildSession(completed: Bool, nowMs: Int64) -> WorkoutSessionRecord? {
        let startedAtMs = liveSessionState.startedAtMs ?? nowMs
        let durationMs = max(1_000, nowMs - startedAtMs)
        var sessionState = liveSessionState
        sessionState.seedFromLiveCounterIfNeeded(
            reps: liveCounterReps,
            durationMs: durationMs,
            detail: liveFallbackCleanDetail
        )
        guard sessionState.hasActivity else { return nil }

        return WorkoutSessionRecord(
            id: "live-\(nowMs)",
            timestampMs: nowMs,
            exerciseKey: startRequest.exercise.key,
            presetKey: startRequest.exercise.presetKey,
            goalReps: startRequest.goalReps,
            completed: completed,
            reps: sessionState.reps,
            successfulAttempts: sessionState.successfulAttempts,
            failedAttempts: sessionState.failedAttempts,
            durationMs: durationMs,
            estimatedKcal: sessionState.estimatedKcal,
            completionRate: sessionState.completionRate,
            attempts: sessionState.attempts
        )
    }

    private var liveCounterTitle: String {
        switch liveTrackingPipeline {
        case .squatCounter:
            return cameraController.squatState.title
        case .pushupCounter:
            return cameraController.pushupState.title
        case .situpCounter:
            return cameraController.situpState.title
        case .barbellPressCounter:
            return cameraController.barbellPressState.title
        case .unavailable:
            return "MODEL PLANNED"
        }
    }

    private var liveCounterDetail: String {
        switch liveTrackingPipeline {
        case .squatCounter:
            return cameraController.squatState.detail
        case .pushupCounter:
            return cameraController.pushupState.detail
        case .situpCounter:
            return cameraController.situpState.detail
        case .barbellPressCounter:
            return cameraController.barbellPressState.detail
        case .unavailable:
            return "This movement is still planned for Live tracking."
        }
    }

    private var liveCounterProgress: Double {
        switch liveTrackingPipeline {
        case .squatCounter:
            return cameraController.squatState.progress
        case .pushupCounter:
            return cameraController.pushupState.progress
        case .situpCounter:
            return cameraController.situpState.progress
        case .barbellPressCounter:
            return cameraController.barbellPressState.progress
        case .unavailable:
            return 0
        }
    }

    private var liveCounterReps: Int {
        switch liveTrackingPipeline {
        case .squatCounter:
            return cameraController.squatState.reps
        case .pushupCounter:
            return cameraController.pushupState.reps
        case .situpCounter:
            return cameraController.situpState.reps
        case .barbellPressCounter:
            return cameraController.barbellPressState.reps
        case .unavailable:
            return 0
        }
    }

    private var liveGaugeTitle: String {
        liveTrackingPipeline == .barbellPressCounter ? "ARC" : "DEPTH"
    }

    private var liveFallbackCleanDetail: String {
        if liveTrackingPipeline == .squatCounter {
            return "Live MediaPipe Squat clean rep counted from camera tracking."
        }

        return "Live MediaPipe \(startRequest.exercise.displayName) clean rep counted from camera tracking."
    }

    private var liveTrackingPipeline: LiveExerciseTrackingPipeline {
        LiveExerciseTrackingPipeline.pipeline(for: startRequest.exercise.key)
    }

    private var liveInstructionIntro: String {
        if liveTrackingPipeline == .squatCounter {
            return "Set the camera first. The counter needs hips, knees, and ankles visible through the full squat."
        }

        if liveTrackingPipeline == .pushupCounter {
            return "Set the camera low and sideways. The counter needs the full plank line and both elbows visible."
        }

        if liveTrackingPipeline == .situpCounter {
            return "Set the camera low from the side. The counter needs shoulders, hips, and knees visible through the full sit-up."
        }

        return "Set the camera first. The counter is strict only when it can see the full press path."
    }

    private var liveInstructionSteps: [(index: String, title: String, detail: String)] {
        if liveTrackingPipeline == .squatCounter {
            return [
                ("01", "FRAME", "Step back until hips, knees, and ankles stay visible."),
                ("02", "START", "Stand tall first so Live can arm the squat counter."),
                ("03", "MOVE", "Squat down with both legs, then return to the same tall stance."),
                ("04", "MISS", "Too shallow, too fast, or uneven reps stay out of REPS and save as MISS.")
            ]
        }

        if liveTrackingPipeline == .pushupCounter {
            return [
                ("01", "FRAME", "Place the phone low from the side so shoulders, elbows, wrists, hips, knees, and ankles stay visible."),
                ("02", "START", "Hold a straight top plank first so Live can arm the push-up counter."),
                ("03", "MOVE", "Lower with both elbows, reach depth, then push back to the same top plank."),
                ("04", "MISS", "Too shallow, too fast, bent-knee, or uneven reps stay out of REPS and save as MISS.")
            ]
        }

        if liveTrackingPipeline == .situpCounter {
            return [
                ("01", "FRAME", "Place the phone low from the side so shoulders, hips, and knees stay visible."),
                ("02", "START", "Begin lying back first so Live can arm the sit-up counter."),
                ("03", "MOVE", "Sit up, reach the top range, then return back down with control."),
                ("04", "MISS", "Short, too fast, or uneven reps stay out of REPS and save as MISS.")
            ]
        }

        return [
            ("01", "FRAME", "Step back until head, elbows, and wrists stay visible."),
            ("02", "START", "Begin with both hands high so Live can arm the counter."),
            ("03", "MOVE", "Press down and back up evenly; pause briefly near lockout."),
            ("04", "MISS", "Short, too fast, or uneven reps stay out of REPS and save as MISS.")
        ]
    }
}
