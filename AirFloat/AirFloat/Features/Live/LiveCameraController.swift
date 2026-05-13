@preconcurrency import AVFoundation
import Combine
import Foundation
@preconcurrency import Vision

enum LiveCameraState: Equatable {
    case idle
    case requestingPermission
    case ready
    case permissionDenied
    case restricted
    case frontCameraUnavailable
    case failed(String)

    var statusLine: String {
        switch self {
        case .idle:
            return "Preparing thin camera baseline."
        case .requestingPermission:
            return "Waiting for camera permission."
        case .ready:
            return "Native front-camera preview baseline is live."
        case .permissionDenied:
            return "Camera access denied."
        case .restricted:
            return "Camera access restricted."
        case .frontCameraUnavailable:
            return "Front camera is unavailable on this runtime."
        case let .failed(message):
            return message
        }
    }

    var canRetry: Bool {
        switch self {
        case .ready, .requestingPermission:
            return false
        case .idle, .permissionDenied, .restricted, .frontCameraUnavailable, .failed:
            return true
        }
    }
}

private enum LiveCameraConfigurationError: Error {
    case frontCameraUnavailable
    case inputCreationFailed
    case inputAttachmentFailed
    case outputAttachmentFailed
}

enum LivePoseRuntimeState: Equatable {
    case idle
    case waitingForCamera
    case warmingUp
    case noPoseDetected(processedFrames: Int)
    case tracking(pointCount: Int, processedFrames: Int)
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "Pose runtime idle"
        case .waitingForCamera:
            return "Waiting for camera"
        case .warmingUp:
            return "Pose probe warming up"
        case .noPoseDetected:
            return "No pose detected yet"
        case .tracking:
            return "Pose landmarks detected"
        case .unavailable:
            return "Pose runtime unavailable"
        case .failed:
            return "Pose runtime failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "No runtime work is active yet."
        case .waitingForCamera:
            return "The pose probe will start only after camera access and a usable front-camera session."
        case .warmingUp:
            return "The camera is live. Waiting for the first frame probe."
        case let .noPoseDetected(processedFrames):
            return "Body-pose probing is active, but no confident body landmarks were found after \(processedFrames) sampled frame(s)."
        case let .tracking(pointCount, processedFrames):
            return "MediaPipe body-pose probing is active. The last sampled frame reported \(pointCount) confident landmark(s) after \(processedFrames) sampled frame(s)."
        case let .unavailable(message):
            return message
        case let .failed(message):
            return message
        }
    }
}

final class LiveCameraController: NSObject, ObservableObject {
    @Published private(set) var state: LiveCameraState = .idle
    @Published private(set) var poseRuntimeState: LivePoseRuntimeState = .idle
    @Published private(set) var barbellPressState: LiveBarbellPressCounterResult = .idle
    @Published private(set) var squatState: LiveSquatCounterResult = .idle
    @Published private(set) var pushupState: LivePushupCounterResult = .idle
    @Published private(set) var situpState: LiveSitupCounterResult = .idle
    @Published private(set) var poseDiagnostics: LivePoseDiagnostics = .empty
    @Published private(set) var latestPoseFrame: LivePoseFrame?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.airfloat.live.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.airfloat.live.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var isPoseRequestInFlight = false
    private var processedPoseFrames = 0
    private var missedPoseFrames = 0
    private var lastPoseRequestStartedAt: TimeInterval = 0
    private var lastSitupFrameDiagnosticAtMs: Int = 0
    private var activeExerciseKey = ExerciseKey.pressBarbell
    private var barbellPressCounter = LiveBarbellPressCounter()
    private var squatCounter = LiveSquatCounter()
    private var pushupCounter = LivePushupCounter()
    private var situpCounter = LiveSitupCounter()
    private var mediaPipePoseSource: MediaPipeLivePoseSource?

    func handleAppear(exerciseKey: ExerciseKey = .pressBarbell) {
        activeExerciseKey = exerciseKey
        publishPoseRuntimeState(.waitingForCamera)
        refreshAuthorizationAndStartIfPossible()
    }

    func handleDisappear() {
        stopSessionIfNeeded()
        publishPoseRuntimeState(.idle)
        publishBarbellPressState(.idle)
        publishSquatState(.idle)
        publishPushupState(.idle)
        publishSitupState(.idle)
        publishPoseDiagnostics(.empty)
        publishLatestPoseFrame(nil)
        mediaPipePoseSource = nil
    }

    func refreshAuthorizationAndStartIfPossible() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            requestCameraAccess()
        case .denied:
            state = .permissionDenied
            publishPoseRuntimeState(.unavailable("Pose probing cannot start without camera access."))
        case .restricted:
            state = .restricted
            publishPoseRuntimeState(.unavailable("Pose probing is blocked because camera access is restricted on this device."))
        @unknown default:
            state = .failed("Unknown camera authorization state.")
            publishPoseRuntimeState(.failed("Pose probing could not start because camera authorization is unknown."))
        }
    }

    private func requestCameraAccess() {
        state = .requestingPermission
        publishPoseRuntimeState(.waitingForCamera)

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }

                if granted {
                    self.configureAndStartSession()
                } else {
                    self.state = .permissionDenied
                }
            }
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.configureSessionIfNeeded()
                self.startSessionIfNeeded()

                DispatchQueue.main.async {
                    self.state = .ready
                }
            } catch LiveCameraConfigurationError.frontCameraUnavailable {
                DispatchQueue.main.async {
                    self.state = .frontCameraUnavailable
                    self.poseRuntimeState = .unavailable("A real front camera is required before the pose probe can run.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .failed("The camera preview baseline could not start.")
                    self.poseRuntimeState = .failed("The pose probe could not start because the camera session failed.")
                }
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }

        guard let cameraDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw LiveCameraConfigurationError.frontCameraUnavailable
        }

        let cameraInput: AVCaptureDeviceInput

        do {
            cameraInput = try AVCaptureDeviceInput(device: cameraDevice)
        } catch {
            throw LiveCameraConfigurationError.inputCreationFailed
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        for input in session.inputs {
            session.removeInput(input)
        }

        guard session.canAddInput(cameraInput) else {
            throw LiveCameraConfigurationError.inputAttachmentFailed
        }

        session.addInput(cameraInput)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw LiveCameraConfigurationError.outputAttachmentFailed
        }

        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoMirroringSupported
        {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        isConfigured = true
    }

    private func startSessionIfNeeded() {
        guard isConfigured, !session.isRunning else { return }
        processedPoseFrames = 0
        missedPoseFrames = 0
        isPoseRequestInFlight = false
        lastPoseRequestStartedAt = 0
        lastSitupFrameDiagnosticAtMs = 0
        barbellPressCounter.reset()
        squatCounter.reset()
        pushupCounter.reset()
        situpCounter.reset()
        if LiveExerciseTrackingPipeline.pipeline(for: activeExerciseKey) == .situpCounter {
            LiveDiagnosticsFileLog.reset()
            LiveDiagnosticsFileLog.append("situp sessionStart exercise=\(activeExerciseKey.rawValue)")
        }
        configureMediaPipePoseSourceIfNeeded()
        session.startRunning()
        publishPoseRuntimeState(.warmingUp)
        publishBarbellPressState(.idle)
        publishSquatState(.idle)
        publishPushupState(.idle)
        publishSitupState(.idle)
        publishPoseDiagnostics(.empty)
        publishLatestPoseFrame(nil)
    }

    private func stopSessionIfNeeded() {
        let captureSession = session

        sessionQueue.async {
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    private func publishPoseRuntimeState(_ nextState: LivePoseRuntimeState) {
        DispatchQueue.main.async {
            self.poseRuntimeState = nextState
        }
    }

    private func publishBarbellPressState(_ nextState: LiveBarbellPressCounterResult) {
        DispatchQueue.main.async {
            self.barbellPressState = nextState
        }
    }

    private func publishSquatState(_ nextState: LiveSquatCounterResult) {
        DispatchQueue.main.async {
            self.squatState = nextState
        }
    }

    private func publishPushupState(_ nextState: LivePushupCounterResult) {
        DispatchQueue.main.async {
            self.pushupState = nextState
        }
    }

    private func publishSitupState(_ nextState: LiveSitupCounterResult) {
        DispatchQueue.main.async {
            self.situpState = nextState
        }
    }

    private func publishPoseDiagnostics(_ nextDiagnostics: LivePoseDiagnostics) {
        DispatchQueue.main.async {
            self.poseDiagnostics = nextDiagnostics
        }
    }

    private func publishLatestPoseFrame(_ frame: LivePoseFrame?) {
        DispatchQueue.main.async {
            self.latestPoseFrame = frame
        }
    }

    private func shouldProbePose(now: TimeInterval) -> Bool {
        guard !isPoseRequestInFlight else { return false }
        return now - lastPoseRequestStartedAt >= poseProbeInterval
    }

    private var poseProbeInterval: TimeInterval {
        switch LiveExerciseTrackingPipeline.pipeline(for: activeExerciseKey) {
        case .pushupCounter, .situpCounter:
            return 0.06
        case .barbellPressCounter, .squatCounter, .unavailable:
            return 0.12
        }
    }

    private func configureMediaPipePoseSourceIfNeeded() {
        guard mediaPipePoseSource == nil else { return }

        do {
            guard let modelPath = MediaPipePoseModelResource.path else {
                publishPoseRuntimeState(.failed("MediaPipe pose model is missing from the app bundle."))
                return
            }

            let source = try MediaPipeLivePoseSource(
                modelPath: modelPath,
                configuration: .configuration(for: activeExerciseKey)
            )
            source.onFrame = { [weak self] sourceFrame in
                self?.handleMediaPipePoseFrame(sourceFrame)
            }
            source.onError = { [weak self] message in
                self?.publishPoseRuntimeState(.failed(message))
            }
            mediaPipePoseSource = source
        } catch {
            mediaPipePoseSource = nil
            publishPoseRuntimeState(.failed("MediaPipe pose source failed to initialize: \(error.localizedDescription)"))
        }
    }

    private func runPoseProbe(on sampleBuffer: CMSampleBuffer) {
        guard let mediaPipePoseSource else {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            runVisionPoseProbe(on: pixelBuffer)
            return
        }

        isPoseRequestInFlight = true
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
        mediaPipePoseSource.process(sampleBuffer: sampleBuffer, timestampMs: timestampMs)
    }

    private func handleMediaPipePoseFrame(_ sourceFrame: MediaPipeLivePoseSourceFrame) {
        processedPoseFrames += 1
        isPoseRequestInFlight = false

        let poseFrame = sourceFrame.frame
        publishLatestPoseFrame(poseFrame)
        let diagnostics = LivePoseDiagnostics.build(from: poseFrame)
        publishPoseDiagnostics(diagnostics)
        logSitupFrameDiagnosticIfNeeded(
            frame: poseFrame,
            diagnostics: diagnostics,
            timestampMs: sourceFrame.timestampMs,
            latencyMs: sourceFrame.latencyMs
        )
        let confidentPointCount = poseFrame.confidentLandmarkCount()
        updateActiveExerciseCounter(
            frame: poseFrame,
            timestampMs: Int64(sourceFrame.timestampMs)
        )

        if confidentPointCount > 0 {
            missedPoseFrames = 0
            publishPoseRuntimeState(
                .tracking(
                    pointCount: confidentPointCount,
                    processedFrames: processedPoseFrames
                )
            )
        } else {
            publishPoseMissIfNeeded()
        }
    }

    private func runVisionPoseProbe(on pixelBuffer: CVPixelBuffer) {
        isPoseRequestInFlight = true
        defer { isPoseRequestInFlight = false }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .leftMirrored,
            options: [:]
        )

        do {
            try handler.perform([request])
            processedPoseFrames += 1

            guard let observation = request.results?.first else {
                publishLatestPoseFrame(nil)
                publishPoseDiagnostics(.empty)
                publishPoseMissIfNeeded()
                return
            }

            let poseFrame = try LivePoseFrame.build(from: observation)
            publishLatestPoseFrame(poseFrame)
            publishPoseDiagnostics(.build(from: poseFrame))
            let confidentPointCount = poseFrame.confidentLandmarkCount()
            let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
            updateActiveExerciseCounter(frame: poseFrame, timestampMs: timestampMs)

            if confidentPointCount > 0 {
                missedPoseFrames = 0
                publishPoseRuntimeState(
                    .tracking(
                        pointCount: confidentPointCount,
                        processedFrames: processedPoseFrames
                    )
                )
            } else {
                publishPoseMissIfNeeded()
            }
        } catch {
            publishPoseRuntimeState(.failed("The Vision pose probe failed while processing camera frames."))
        }
    }

    private func publishPoseMissIfNeeded() {
        missedPoseFrames += 1
        guard missedPoseFrames >= 3 else { return }
        publishPoseRuntimeState(.noPoseDetected(processedFrames: processedPoseFrames))
    }

    private func updateActiveExerciseCounter(frame: LivePoseFrame, timestampMs: Int64) {
        switch LiveExerciseTrackingPipeline.pipeline(for: activeExerciseKey) {
        case .barbellPressCounter:
            let barbellState = barbellPressCounter.update(frame: frame, timestampMs: timestampMs)
            publishBarbellPressState(barbellState)
        case .squatCounter:
            let nextSquatState = squatCounter.update(frame: frame, timestampMs: timestampMs)
            publishSquatState(nextSquatState)
        case .pushupCounter:
            let nextPushupState = pushupCounter.update(frame: frame, timestampMs: timestampMs)
            publishPushupState(nextPushupState)
        case .situpCounter:
            let nextSitupState = situpCounter.update(frame: frame, timestampMs: timestampMs)
            publishSitupState(nextSitupState)
        case .unavailable:
            publishBarbellPressState(.idle)
            publishSquatState(.idle)
            publishPushupState(.idle)
            publishSitupState(.idle)
        }
    }

    private func logSitupFrameDiagnosticIfNeeded(
        frame: LivePoseFrame,
        diagnostics: LivePoseDiagnostics,
        timestampMs: Int,
        latencyMs: Double
    ) {
        guard LiveExerciseTrackingPipeline.pipeline(for: activeExerciseKey) == .situpCounter else { return }
        guard timestampMs - lastSitupFrameDiagnosticAtMs >= 500 else { return }
        lastSitupFrameDiagnosticAtMs = timestampMs

        let message = [
            "situpFrame",
            "frames=\(processedPoseFrames)",
            "landmarks=\(frame.landmarkCount)",
            "confident=\(diagnostics.confidentLandmarkCount)",
            "latencyMs=\(String(format: "%.1f", latencyMs))",
            "LS=\(diagnosticConfidenceText(diagnostics.leftShoulder.confidence))",
            "LH=\(diagnosticConfidenceText(diagnostics.leftHip.confidence))",
            "LK=\(diagnosticConfidenceText(diagnostics.leftKnee.confidence))",
            "RS=\(diagnosticConfidenceText(diagnostics.rightShoulder.confidence))",
            "RH=\(diagnosticConfidenceText(diagnostics.rightHip.confidence))",
            "RK=\(diagnosticConfidenceText(diagnostics.rightKnee.confidence))",
        ].joined(separator: " ")
        LiveDiagnosticsFileLog.append("[AirFloatTune] \(message)")
    }

    private func diagnosticConfidenceText(_ confidence: Float?) -> String {
        guard let confidence else { return "--" }
        return String(format: "%.2f", confidence)
    }
}

extension LiveCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime

        guard shouldProbePose(now: now) else { return }
        lastPoseRequestStartedAt = now
        runPoseProbe(on: sampleBuffer)
    }
}
