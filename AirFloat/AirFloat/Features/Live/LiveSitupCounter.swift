import Foundation

enum LiveSitupCondition: Equatable {
    case badStart
    case tracking
    case repCounted
    case rangeTooSmall
    case trackingLost
}

enum LiveSitupRejectReason: Equatable {
    case insufficientTop
    case tooFast
    case asymmetricRange

    var missedAttemptDetail: String {
        switch self {
        case .insufficientTop:
            return "Missed sit-up: range was not deep enough."
        case .tooFast:
            return "Missed sit-up: tempo was too fast."
        case .asymmetricRange:
            return "Missed sit-up: left/right range mismatch."
        }
    }

    var notCountedHint: String {
        switch self {
        case .insufficientTop:
            return "Not counted: complete the full down-up-down range."
        case .tooFast:
            return "Not counted: movement is too fast."
        case .asymmetricRange:
            return "Not counted: left/right range mismatch."
        }
    }

    var debugLabel: String {
        switch self {
        case .insufficientTop:
            return "INSUFFICIENT_DEPTH"
        case .tooFast:
            return "TOO_FAST"
        case .asymmetricRange:
            return "ASYMMETRIC_RANGE"
        }
    }
}

struct LiveSitupCounterResult: Equatable {
    let reps: Int
    let progress: Double
    let condition: LiveSitupCondition
    let leftHipAngle: Double?
    let rightHipAngle: Double?
    let rejectReason: LiveSitupRejectReason?
    let rejectEventID: Int?
    let isCycleActive: Bool
    let lastRepAtMs: Int64
    let debugEvent: String

    static let idle = LiveSitupCounterResult(
        reps: 0,
        progress: 0,
        condition: .badStart,
        leftHipAngle: nil,
        rightHipAngle: nil,
        rejectReason: nil,
        rejectEventID: nil,
        isCycleActive: false,
        lastRepAtMs: 0,
        debugEvent: "Waiting for Sit-up pose."
    )

    var title: String {
        switch condition {
        case .badStart:
            return "LIE BACK"
        case .tracking:
            return isCycleActive ? "SIT UP" : "READY"
        case .repCounted:
            return "CLEAN REP"
        case .rangeTooSmall:
            return "RANGE TOO SMALL"
        case .trackingLost:
            return "TRACK LOST"
        }
    }

    var detail: String {
        let progressText = "\(Int((progress * 100).rounded()))% RANGE"
        let angleText = [leftHipAngle, rightHipAngle]
            .compactMap { $0 }
            .map { "\(Int($0.rounded()))deg" }
            .joined(separator: " / ")

        switch condition {
        case .badStart:
            return "Start lying back with shoulders, hips, and knees visible."
        case .tracking:
            return angleText.isEmpty ? "\(reps) reps - \(progressText)" : "\(reps) reps - \(progressText) - \(angleText)"
        case .repCounted:
            return "\(reps) reps - clean sit-up detected."
        case .rangeTooSmall:
            if let rejectReason {
                return rejectReason.notCountedHint
            }
            return "\(reps) reps - complete the full sit-up range."
        case .trackingLost:
            return "Camera lost shoulders, hips, or knees. Re-center and go again."
        }
    }
}

struct LiveSitupCounter {
    private enum Phase {
        case idleTop
        case descending
        case ascending
    }

    private let topThresholdDeg = 150.0
    private let bottomThresholdDeg = 108.0
    private let minRepDurationMs: Int64 = 340
    private let minDepthTravelDeg = 24.0
    private let minBottomTravelDeg = 40.0
    private let minBothSidesTravelDeg = 10.0
    private let minSymmetryRatio = 0.45
    private let minAsymmetryCheckTravelDeg = 34.0
    private let emaAlpha = 0.35
    private let trackingLostFramesForCondition = 3
    private let maxTrackingGapFramesBeforeReset = 20
    private let minCycleFrames = 6
    private let minInterRepGapMs: Int64 = 300
    private let startCycleDeltaDeg = 6.0
    private let completionReturnSlackDeg = 6.0
    private let completionReturnFloorDeg = 126.0
    private let minTopReadyAngleDeg = 134.0
    private let topReadySlackDeg = 12.0
    private let startDebounceFrames = 2
    private let minStartDropPerFrameDeg = 0.6
    private let startAsymmetryWindowFrames = 4
    private let startAsymmetryTravelDeg = 10.0
    private let maxStartArmMs: Int64 = 1_200
    // Android's SitupCounter consumes MediaPipe coordinates directly and does not gate
    // hips/knees by visibility. Floor poses often report low visibility even when
    // coordinates are still usable, so Sit-up uses coordinates first and logs
    // visibility separately through Live diagnostics.
    private let landmarkMinConfidence: Float = 0.0

    private var reps = 0
    private var phase: Phase = .idleTop
    private var emaLeft: Double?
    private var emaRight: Double?
    private var trackingGapFrames = 0
    private var hasSeenValidPose = false
    private var topReady = false
    private var observedTopLeft = -Double.greatestFiniteMagnitude
    private var observedTopRight = -Double.greatestFiniteMagnitude
    private var prevDrive: Double?
    private var startBelowThresholdFrames = 0
    private var armedTopLeft = Double.nan
    private var armedTopRight = Double.nan
    private var armedTopTs: Int64 = 0

    private var cycleStartTs: Int64 = 0
    private var cycleTopLeft = 0.0
    private var cycleTopRight = 0.0
    private var cycleMinLeft = Double.greatestFiniteMagnitude
    private var cycleMinRight = Double.greatestFiniteMagnitude
    private var cycleFrameCount = 0
    private var lastCycleEndTs: Int64 = 0
    private var lastRepTs: Int64 = 0
    private var cycleStartedAsymmetric = false
    private var cycleReachedBottomByAbsolute = false
    private var rejectEventID = 0
    private var lastDiagLogTs: Int64 = 0
    private var lastDiagPhase: Phase?
    private var lastDiagCondition: LiveSitupCondition?
    private var lastDiagTopReady = false
    private let diagLogIntervalMs: Int64 = 250

    mutating func reset() {
        reps = 0
        phase = .idleTop
        emaLeft = nil
        emaRight = nil
        trackingGapFrames = 0
        hasSeenValidPose = false
        topReady = false
        observedTopLeft = -Double.greatestFiniteMagnitude
        observedTopRight = -Double.greatestFiniteMagnitude
        prevDrive = nil
        startBelowThresholdFrames = 0
        resetStartArm()
        lastCycleEndTs = 0
        lastRepTs = 0
        cycleStartedAsymmetric = false
        rejectEventID = 0
        lastDiagLogTs = 0
        lastDiagPhase = nil
        lastDiagCondition = nil
        lastDiagTopReady = false
        resetCycle()
    }

    mutating func update(frame: LivePoseFrame, timestampMs: Int64) -> LiveSitupCounterResult {
        guard let angles = extractHipAngles(frame) else {
            onTrackingGap()
            let debugEvent = trackingGapFrames >= trackingLostFramesForCondition
                ? "Tracking gap: shoulders/hips/knees dropped."
                : "Waiting for shoulders, hips, and knees."
            if trackingGapFrames == trackingLostFramesForCondition ||
                trackingGapFrames == maxTrackingGapFramesBeforeReset
            {
                printTune("situp trackingGap frames=\(trackingGapFrames) phase=\(phaseName) topReady=\(topReady) reps=\(reps)")
            }
            let condition: LiveSitupCondition = trackingGapFrames >= trackingLostFramesForCondition ? .trackingLost : .badStart
            logDiagSnapshot(
                timestampMs: timestampMs,
                left: nil,
                right: nil,
                drive: nil,
                progress: 0,
                condition: condition,
                rejectReason: nil,
                note: "no_pose"
            )
            return LiveSitupCounterResult(
                reps: reps,
                progress: 0,
                condition: condition,
                leftHipAngle: nil,
                rightHipAngle: nil,
                rejectReason: nil,
                rejectEventID: nil,
                isCycleActive: phase != .idleTop,
                lastRepAtMs: lastRepTs,
                debugEvent: debugEvent
            )
        }

        trackingGapFrames = 0
        hasSeenValidPose = true

        let left = ema(previous: emaLeft, newValue: angles.leftHip)
        let right = ema(previous: emaRight, newValue: angles.rightHip)
        emaLeft = left
        emaRight = right

        guard let effectiveLeft = left ?? right, let effectiveRight = right ?? left else {
            onTrackingGap()
            return .idle
        }

        let drive = min(effectiveLeft, effectiveRight)
        let eventLeft = min(effectiveLeft, angles.leftHip ?? effectiveLeft)
        let eventRight = min(effectiveRight, angles.rightHip ?? effectiveRight)
        let eventDrive = min(eventLeft, eventRight)
        let progress = angleToProgress(drive)
        var rejectReason: LiveSitupRejectReason?
        var currentRejectEventID: Int?
        var repCompleted = false
        var debugEvent = "phase=\(phaseName) L=\(fmt1(effectiveLeft)) R=\(fmt1(effectiveRight)) drive=\(fmt1(drive)) progress=\(Int((progress * 100).rounded()))%"

        switch phase {
        case .idleTop:
            updateObservedTop(left: effectiveLeft, right: effectiveRight)
            let topReference = currentTopReference()
            topReady = observedTopAngle >= minTopReadyAngleDeg
            let nearTop = topReady && drive >= topReference - topReadySlackDeg

            if nearTop {
                let topLeft = currentTopLeftReference() ?? min(effectiveLeft, topThresholdDeg)
                let topRight = currentTopRightReference() ?? min(effectiveRight, topThresholdDeg)
                armStartFromTop(
                    left: topLeft,
                    right: topRight,
                    timestampMs: timestampMs
                )
                startBelowThresholdFrames = 0
            }

            let gapOk = timestampMs - lastCycleEndTs >= minInterRepGapMs
            let descending = prevDrive.map { ($0 - drive) >= minStartDropPerFrameDeg } ?? false
            let armExpired = armedTopTs > 0 && timestampMs - armedTopTs > maxStartArmMs
            let armedTopDrive = armExpired ? nil : armedTopDriveOrNil()
            let startDrop = armedTopDrive.map { max(0, $0 - drive) }
            let canStart =
                armedTopDrive != nil &&
                !nearTop &&
                topReady &&
                gapOk &&
                descending &&
                startDrop.map { $0 >= startCycleDeltaDeg } == true

            if armExpired {
                resetStartArm()
            }

            let hasReachedBottomDuringStart = eventDrive <= bottomThresholdDeg
            if !nearTop && canStart {
                startBelowThresholdFrames = hasReachedBottomDuringStart ? startDebounceFrames : startBelowThresholdFrames + 1
            } else if !nearTop {
                startBelowThresholdFrames = 0
            }

            if startBelowThresholdFrames >= startDebounceFrames && armedTopDrive != nil {
                phase = .descending
                cycleStartTs = timestampMs
                cycleTopLeft = armedTopLeft
                cycleTopRight = armedTopRight
                cycleMinLeft = eventLeft
                cycleMinRight = eventRight
                cycleFrameCount = 1
                startBelowThresholdFrames = 0
                resetStartArm()
                debugEvent = "Cycle started: down-to-up sit-up motion armed."
                printTune(
                    "situp cycleStart drive=\(fmt1(drive)) left=\(fmt1(effectiveLeft)) right=\(fmt1(effectiveRight)) topRef=\(fmt1(topReference)) topL=\(fmt1(cycleTopLeft)) topR=\(fmt1(cycleTopRight)) bottom=\(fmt1(bottomThresholdDeg))"
                )
            }

        case .descending:
            cycleFrameCount += 1
            cycleMinLeft = min(cycleMinLeft, eventLeft)
            cycleMinRight = min(cycleMinRight, eventRight)

            let reachedBottomByAbsolute = eventDrive <= bottomThresholdDeg
            let reachedBottomByTravel = cycleTopDrive - eventDrive >= minBottomTravelDeg
            if reachedBottomByAbsolute || reachedBottomByTravel {
                cycleReachedBottomByAbsolute = reachedBottomByAbsolute
                phase = .ascending
                debugEvent = reachedBottomByAbsolute ? "Bottom reached by hip angle." : "Bottom reached by travel."
                printTune(
                    "situp bottomReached drive=\(fmt1(drive)) eventDrive=\(fmt1(eventDrive)) travel=\(fmt1(cycleTopDrive - eventDrive)) abs=\(reachedBottomByAbsolute) travelGate=\(reachedBottomByTravel)"
                )
            } else if returnedNearCycleTop(drive: drive) {
                let attemptTravel = attemptMaxTravel()
                if attemptTravel >= 8 {
                    rejectReason = validateAttempt(timestampMs: timestampMs, reachedBottom: false)
                    currentRejectEventID = nextRejectEventIDIfNeeded(rejectReason)
                    if let rejectReason {
                        debugEvent = "Rejected before bottom: \(rejectReason.debugLabel)"
                        printTune("situp repRejected beforeBottom reason=\(rejectReason.debugLabel)")
                    }
                }
                phase = .idleTop
                lastCycleEndTs = timestampMs
                topReady = drive >= minTopReadyAngleDeg
                setObservedTopFromCurrent(left: effectiveLeft, right: effectiveRight)
                resetStartArm()
                resetCycle()
            }

        case .ascending:
            cycleFrameCount += 1
            cycleMinLeft = min(cycleMinLeft, eventLeft)
            cycleMinRight = min(cycleMinRight, eventRight)

            let returnedNearStart = returnedNearCycleTop(drive: drive)
            if returnedNearStart {
                let attemptTravel = attemptMaxTravel()
                if attemptTravel >= 8 {
                    let reject = validateAttempt(timestampMs: timestampMs, reachedBottom: true)
                    if let reject {
                        rejectReason = reject
                        currentRejectEventID = nextRejectEventIDIfNeeded(rejectReason)
                        debugEvent = "Rejected at top: \(reject.debugLabel)"
                        printTune("situp repRejected atTop reason=\(reject.debugLabel)")
                    } else {
                        reps += 1
                        lastRepTs = timestampMs
                        repCompleted = true
                        debugEvent = "Clean rep counted."
                        printTune("situp rep=\(reps) minL=\(fmt1(cycleMinLeft)) maxL=\(fmt1(cycleTopLeft)) minR=\(fmt1(cycleMinRight)) maxR=\(fmt1(cycleTopRight))")
                    }
                }
                phase = .idleTop
                lastCycleEndTs = timestampMs
                topReady = drive >= minTopReadyAngleDeg
                setObservedTopFromCurrent(left: effectiveLeft, right: effectiveRight)
                resetStartArm()
                resetCycle()
            }
        }

        prevDrive = drive

        let condition: LiveSitupCondition
        if repCompleted {
            condition = .repCounted
        } else if rejectReason != nil {
            condition = rejectReason == .tooFast ? .tracking : .rangeTooSmall
        } else if !hasSeenValidPose {
            condition = .badStart
        } else {
            condition = .tracking
        }

        logDiagSnapshot(
            timestampMs: timestampMs,
            left: effectiveLeft,
            right: effectiveRight,
            drive: drive,
            progress: progress,
            condition: condition,
            rejectReason: rejectReason
        )

        return LiveSitupCounterResult(
            reps: reps,
            progress: progress,
            condition: condition,
            leftHipAngle: effectiveLeft,
            rightHipAngle: effectiveRight,
            rejectReason: rejectReason,
            rejectEventID: currentRejectEventID,
            isCycleActive: phase != .idleTop,
            lastRepAtMs: lastRepTs,
            debugEvent: debugEvent
        )
    }

    private mutating func onTrackingGap() {
        trackingGapFrames += 1
        if trackingGapFrames > maxTrackingGapFramesBeforeReset {
            phase = .idleTop
            topReady = false
            observedTopLeft = -Double.greatestFiniteMagnitude
            observedTopRight = -Double.greatestFiniteMagnitude
            prevDrive = nil
            resetStartArm()
            resetCycle()
        }
    }

    private mutating func resetCycle() {
        cycleStartTs = 0
        cycleTopLeft = 0
        cycleTopRight = 0
        cycleMinLeft = Double.greatestFiniteMagnitude
        cycleMinRight = Double.greatestFiniteMagnitude
        cycleFrameCount = 0
        cycleStartedAsymmetric = false
        cycleReachedBottomByAbsolute = false
    }

    private mutating func resetStartArm() {
        startBelowThresholdFrames = 0
        armedTopLeft = Double.nan
        armedTopRight = Double.nan
        armedTopTs = 0
    }

    private mutating func armStartFromTop(left: Double, right: Double, timestampMs: Int64) {
        armedTopLeft = left
        armedTopRight = right
        armedTopTs = timestampMs
    }

    private func armedTopDriveOrNil() -> Double? {
        guard armedTopLeft.isFinite, armedTopRight.isFinite else { return nil }
        return min(armedTopLeft, armedTopRight)
    }

    private mutating func validateAttempt(timestampMs: Int64, reachedBottom: Bool) -> LiveSitupRejectReason? {
        guard cycleMinLeft.isFinite, cycleMinRight.isFinite else {
            return .insufficientTop
        }

        let travelLeft = max(0, cycleTopLeft - cycleMinLeft)
        let travelRight = max(0, cycleTopRight - cycleMinRight)
        let highTravel = max(travelLeft, travelRight)
        let lowTravel = min(travelLeft, travelRight)

        if !reachedBottom || highTravel < minDepthTravelDeg {
            return .insufficientTop
        }

        if cycleFrameCount < minCycleFrames {
            return .tooFast
        }

        let durationMs = cycleStartTs > 0 ? timestampMs - cycleStartTs : Int64.max
        if durationMs > 0 && durationMs < minRepDurationMs {
            return .tooFast
        }

        if !cycleReachedBottomByAbsolute && highTravel < minBottomTravelDeg {
            return .insufficientTop
        }

        if lowTravel < minBothSidesTravelDeg {
            return .asymmetricRange
        }

        let ratio = lowTravel / max(1, highTravel)
        if highTravel >= minAsymmetryCheckTravelDeg && lowTravel >= minDepthTravelDeg && ratio < minSymmetryRatio {
            return .asymmetricRange
        }

        return nil
    }

    private func attemptMaxTravel() -> Double {
        max(max(0, cycleTopLeft - cycleMinLeft), max(0, cycleTopRight - cycleMinRight))
    }

    private mutating func logDiagSnapshot(
        timestampMs: Int64,
        left: Double?,
        right: Double?,
        drive: Double?,
        progress: Double,
        condition: LiveSitupCondition,
        rejectReason: LiveSitupRejectReason?,
        note: String? = nil
    ) {
        let shouldLog =
            timestampMs - lastDiagLogTs >= diagLogIntervalMs ||
            phase != lastDiagPhase ||
            condition != lastDiagCondition ||
            topReady != lastDiagTopReady ||
            rejectReason != nil

        guard shouldLog else { return }

        lastDiagLogTs = timestampMs
        lastDiagPhase = phase
        lastDiagCondition = condition
        lastDiagTopReady = topReady

        var message = "situpDiag phase=\(phaseName)"
        message += " reps=\(reps)"
        message += " cond=\(condition.debugLogLabel)"
        message += " reject=\(rejectReason?.debugLabel ?? "-")"
        message += " topReady=\(topReady)"
        message += " topRef=\(fmt1OrDash(currentTopReferenceOrNil()))"
        message += " gap=\(trackingGapFrames)"
        message += " progress=\(fmt1(progress * 100))%"
        message += " drive=\(fmt1OrDash(drive))"
        message += " left=\(fmt1OrDash(left))"
        message += " right=\(fmt1OrDash(right))"
        message += " cycleFrames=\(cycleFrameCount)"
        message += " travelL=\(fmt1(currentTravel(start: cycleTopLeft, minValue: cycleMinLeft)))"
        message += " travelR=\(fmt1(currentTravel(start: cycleTopRight, minValue: cycleMinRight)))"
        if let note {
            message += " note=\(note)"
        }
        printTune(message)
    }

    private mutating func updateStartAsymmetryLatch(currentLeft: Double, currentRight: Double) {
        guard !cycleStartedAsymmetric,
              cycleFrameCount > 0,
              cycleFrameCount <= startAsymmetryWindowFrames
        else {
            return
        }

        let travelLeft = max(0, cycleTopLeft - currentLeft)
        let travelRight = max(0, cycleTopRight - currentRight)
        let highTravel = max(travelLeft, travelRight)
        guard highTravel >= startAsymmetryTravelDeg else { return }

        let lowTravel = min(travelLeft, travelRight)
        let ratio = lowTravel / max(1, highTravel)
        if lowTravel < minBothSidesTravelDeg || ratio < minSymmetryRatio {
            cycleStartedAsymmetric = true
        }
    }

    private var cycleTopDrive: Double {
        min(cycleTopLeft, cycleTopRight)
    }

    private func returnedNearCycleTop(drive: Double) -> Bool {
        let strictReturn = cycleTopDrive - completionReturnSlackDeg
        let practicalReturn = max(completionReturnFloorDeg, minTopReadyAngleDeg - 8.0)
        return drive >= min(strictReturn, practicalReturn)
    }

    private mutating func updateObservedTop(left: Double, right: Double) {
        observedTopLeft = max(observedTopLeft, left)
        observedTopRight = max(observedTopRight, right)
    }

    private mutating func setObservedTopFromCurrent(left: Double, right: Double) {
        observedTopLeft = left
        observedTopRight = right
    }

    private func currentTopReference() -> Double {
        currentTopReferenceOrNil() ?? topThresholdDeg
    }

    private func currentTopReferenceOrNil() -> Double? {
        let left = currentTopLeftReference()
        let right = currentTopRightReference()
        switch (left, right) {
        case let (.some(left), .some(right)):
            return min(left, right)
        case let (.some(left), .none):
            return left
        case let (.none, .some(right)):
            return right
        case (.none, .none):
            return nil
        }
    }

    private func currentTopLeftReference() -> Double? {
        observedTopLeft > -Double.greatestFiniteMagnitude / 2 ? min(observedTopLeft, topThresholdDeg) : nil
    }

    private func currentTopRightReference() -> Double? {
        observedTopRight > -Double.greatestFiniteMagnitude / 2 ? min(observedTopRight, topThresholdDeg) : nil
    }

    private var observedTopAngle: Double {
        currentTopReferenceOrNil() ?? -Double.greatestFiniteMagnitude
    }

    private mutating func nextRejectEventIDIfNeeded(_ reason: LiveSitupRejectReason?) -> Int? {
        guard reason != nil else { return nil }
        rejectEventID += 1
        return rejectEventID
    }

    private func angleToProgress(_ driveAngle: Double) -> Double {
        let span = max(1, topThresholdDeg - bottomThresholdDeg)
        return ((topThresholdDeg - driveAngle) / span).clamped(to: 0...1)
    }

    private func extractHipAngles(_ frame: LivePoseFrame) -> SitupAngles? {
        let left = angleDeg(
            frame.landmark(named: LivePoseLandmarkName.leftShoulder, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.leftHip, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.leftKnee, minConfidence: landmarkMinConfidence)
        )
        let right = angleDeg(
            frame.landmark(named: LivePoseLandmarkName.rightShoulder, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.rightHip, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.rightKnee, minConfidence: landmarkMinConfidence)
        )
        guard left != nil || right != nil else { return nil }
        return SitupAngles(leftHip: left, rightHip: right)
    }

    private func angleDeg(_ a: LivePoseLandmark?, _ b: LivePoseLandmark?, _ c: LivePoseLandmark?) -> Double? {
        guard let a, let b, let c else { return nil }
        let bax = a.x - b.x
        let bay = a.y - b.y
        let bcx = c.x - b.x
        let bcy = c.y - b.y
        let normBA = sqrt(bax * bax + bay * bay)
        let normBC = sqrt(bcx * bcx + bcy * bcy)
        guard normBA >= 1e-6, normBC >= 1e-6 else { return nil }
        let dotProduct = bax * bcx + bay * bcy
        let cosine = (dotProduct / (normBA * normBC)).clamped(to: -1...1)
        return acos(cosine) * 180 / Double.pi
    }

    private func ema(previous: Double?, newValue: Double?) -> Double? {
        guard let newValue else { return previous }
        guard let previous else { return newValue }
        return emaAlpha * newValue + (1 - emaAlpha) * previous
    }

    private var phaseName: String {
        switch phase {
        case .idleTop:
            return "IDLE_TOP"
        case .descending:
            return "DESCENDING"
        case .ascending:
            return "ASCENDING"
        }
    }

    private func fmt1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func fmt1OrDash(_ value: Double?) -> String {
        value.map { fmt1($0) } ?? "--"
    }

    private func currentTravel(start: Double, minValue: Double) -> Double {
        guard start.isFinite, minValue.isFinite else { return 0 }
        return max(0, start - minValue)
    }

    private func printTune(_ message: String) {
        print("[AirFloatTune] \(message)")
        LiveDiagnosticsFileLog.append("[AirFloatTune] \(message)")
    }

    private struct SitupAngles {
        let leftHip: Double?
        let rightHip: Double?
    }
}

private extension LiveSitupCondition {
    var debugLogLabel: String {
        switch self {
        case .badStart:
            return "BAD_START"
        case .tracking:
            return "TRACKING"
        case .repCounted:
            return "REP_COUNTED"
        case .rangeTooSmall:
            return "RANGE_TOO_SMALL"
        case .trackingLost:
            return "TRACKING_LOST"
        }
    }
}

enum LiveDiagnosticsFileLog {
    private static let queue = DispatchQueue(label: "com.airfloat.live.diagnostics.file")
    private static let maxFileBytes: UInt64 = 512_000

    static func reset() {
        queue.async {
            let url = logURL()
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func append(_ line: String) {
        queue.async {
            let url = logURL()
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            rotateIfNeeded(url: url)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let payload = "\(timestamp) \(line)\n"
            guard let data = payload.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url)
            {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func rotateIfNeeded(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size >= maxFileBytes
        else {
            return
        }

        let archiveURL = url.deletingPathExtension().appendingPathExtension("previous.log")
        try? FileManager.default.removeItem(at: archiveURL)
        try? FileManager.default.moveItem(at: url, to: archiveURL)
    }

    private static func logURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("AirFloatDiagnostics", isDirectory: true)
            .appendingPathComponent("live_situp.log")
    }
}

private extension LivePoseFrame {
    func landmark(named name: String, minConfidence: Float) -> LivePoseLandmark? {
        landmarks.first { $0.name == name && $0.confidence >= minConfidence }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
