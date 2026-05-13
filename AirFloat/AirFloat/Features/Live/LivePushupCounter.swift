import Foundation

enum LivePushupCondition: Equatable {
    case badStart
    case tracking
    case repCounted
    case rangeTooSmall
    case trackingLost
}

enum LivePushupRejectReason: Equatable {
    case invalidBottomAngle
    case insufficientTop
    case tooFast
    case asymmetricRange

    var missedAttemptDetail: String {
        switch self {
        case .invalidBottomAngle:
            return "Missed push-up: unstable bottom position."
        case .insufficientTop:
            return "Missed push-up: depth was not low enough."
        case .tooFast:
            return "Missed push-up: tempo was too fast."
        case .asymmetricRange:
            return "Missed push-up: left/right range mismatch."
        }
    }

    var notCountedHint: String {
        switch self {
        case .invalidBottomAngle:
            return "Not counted: unstable bottom position."
        case .insufficientTop:
            return "Not counted: go lower."
        case .tooFast:
            return "Not counted: movement is too fast."
        case .asymmetricRange:
            return "Not counted: left/right range mismatch."
        }
    }

    var debugLabel: String {
        switch self {
        case .invalidBottomAngle:
            return "INVALID_BOTTOM_ANGLE"
        case .insufficientTop:
            return "INSUFFICIENT_DEPTH"
        case .tooFast:
            return "TOO_FAST"
        case .asymmetricRange:
            return "ASYMMETRIC_RANGE"
        }
    }
}

struct LivePushupCounterResult: Equatable {
    let reps: Int
    let progress: Double
    let condition: LivePushupCondition
    let leftElbowAngle: Double?
    let rightElbowAngle: Double?
    let rejectReason: LivePushupRejectReason?
    let rejectEventID: Int?
    let isCycleActive: Bool
    let lastRepAtMs: Int64
    let debugEvent: String

    static let idle = LivePushupCounterResult(
        reps: 0,
        progress: 0,
        condition: .badStart,
        leftElbowAngle: nil,
        rightElbowAngle: nil,
        rejectReason: nil,
        rejectEventID: nil,
        isCycleActive: false,
        lastRepAtMs: 0,
        debugEvent: "Waiting for Push-up pose."
    )

    var title: String {
        switch condition {
        case .badStart:
            return "PLANK READY"
        case .tracking:
            return isCycleActive ? "PUSH" : "READY"
        case .repCounted:
            return "CLEAN REP"
        case .rangeTooSmall:
            return "RANGE TOO SMALL"
        case .trackingLost:
            return "TRACK LOST"
        }
    }

    var detail: String {
        let progressText = "\(Int((progress * 100).rounded()))% DEPTH"
        let angleText = [leftElbowAngle, rightElbowAngle]
            .compactMap { $0 }
            .map { "\(Int($0.rounded()))deg" }
            .joined(separator: " / ")

        switch condition {
        case .badStart:
            return "Start in a straight plank with shoulders, elbows, wrists, hips, knees, and ankles visible."
        case .tracking:
            return angleText.isEmpty ? "\(reps) reps - \(progressText)" : "\(reps) reps - \(progressText) - \(angleText)"
        case .repCounted:
            return "\(reps) reps - clean push-up detected."
        case .rangeTooSmall:
            if let rejectReason {
                return rejectReason.notCountedHint
            }
            return "\(reps) reps - go lower before pushing back up."
        case .trackingLost:
            return "Camera lost the push-up line. Re-center and go again."
        }
    }
}

struct LivePushupCounter {
    private enum Phase {
        case idleTop
        case descending
        case ascending
    }

    private let topThresholdDeg = 142.0
    private let bottomThresholdDeg = 98.0
    private let minBottomElbowDeg = 35.0
    private let minLegExtensionDeg = 140.0
    private let minRepDurationMs: Int64 = 300
    private let minDepthTravelDeg = 22.0
    private let minBottomTravelDeg = 36.0
    private let minBothSidesTravelDeg = 10.0
    private let minSymmetryRatio = 0.40
    private let minAsymmetryCheckTravelDeg = 30.0
    private let emaAlpha = 0.35
    private let trackingLostFramesForCondition = 3
    private let maxTrackingGapFramesBeforeReset = 20
    private let minCycleFrames = 4
    private let minInterRepGapMs: Int64 = 300
    private let startCycleDeltaDeg = 6.0
    private let completionReturnSlackDeg = 6.0
    private let minStartDropPerFrameDeg = 0.6
    private let minAttemptTravelForRejectDeg = 10.0
    private let startAsymmetryWindowFrames = 3
    private let startAsymmetryTravelDeg = 24.0
    private let startAsymmetryMinRatio = 0.30
    private let topReadySlackDeg = 5.0
    private let badStanceFramesForCondition = 3
    private let landmarkMinConfidence: Float = 0.15

    private var reps = 0
    private var phase: Phase = .idleTop
    private var emaLeft: Double?
    private var emaRight: Double?
    private var trackingGapFrames = 0
    private var hasSeenValidPose = false
    private var badStanceFrames = 0
    private var topReady = false

    private var cycleStartTs: Int64 = 0
    private var cycleStartAvg = 0.0
    private var cycleStartLeft = 0.0
    private var cycleStartRight = 0.0
    private var cycleMinLeft = Double.greatestFiniteMagnitude
    private var cycleMinRight = Double.greatestFiniteMagnitude
    private var cycleFrameCount = 0
    private var lastCycleEndTs: Int64 = 0
    private var lastRepTs: Int64 = 0
    private var prevDrive: Double?
    private var startBelowThresholdFrames = 0
    private var cycleStartedAsymmetric = false
    private var cycleReachedBottomByAbsolute = false
    private var rejectEventID = 0

    mutating func reset() {
        reps = 0
        phase = .idleTop
        emaLeft = nil
        emaRight = nil
        trackingGapFrames = 0
        hasSeenValidPose = false
        badStanceFrames = 0
        topReady = false
        lastCycleEndTs = 0
        lastRepTs = 0
        prevDrive = nil
        startBelowThresholdFrames = 0
        cycleStartedAsymmetric = false
        rejectEventID = 0
        resetCycle()
    }

    mutating func update(frame: LivePoseFrame, timestampMs: Int64) -> LivePushupCounterResult {
        guard let angles = extractAngles(frame) else {
            onTrackingGap()
            let fallbackDrive = min(emaLeft ?? topThresholdDeg, emaRight ?? topThresholdDeg)
            return LivePushupCounterResult(
                reps: reps,
                progress: angleToProgress(fallbackDrive),
                condition: trackingGapFrames >= trackingLostFramesForCondition ? .trackingLost : .badStart,
                leftElbowAngle: nil,
                rightElbowAngle: nil,
                rejectReason: nil,
                rejectEventID: nil,
                isCycleActive: phase != .idleTop,
                lastRepAtMs: lastRepTs,
                debugEvent: trackingGapFrames >= trackingLostFramesForCondition
                    ? "Tracking gap: push-up landmarks dropped."
                    : "Waiting for shoulders, elbows, wrists, hips, knees, and ankles."
            )
        }

        trackingGapFrames = 0
        hasSeenValidPose = true

        let left = ema(previous: emaLeft, newValue: angles.leftElbow ?? angles.rightElbow)
        let right = ema(previous: emaRight, newValue: angles.rightElbow ?? angles.leftElbow)
        emaLeft = left
        emaRight = right

        guard let effectiveLeft = left, let effectiveRight = right else {
            onTrackingGap()
            return .idle
        }

        let drive = min(effectiveLeft, effectiveRight)
        let eventLeft = min(effectiveLeft, angles.leftElbow ?? effectiveLeft)
        let eventRight = min(effectiveRight, angles.rightElbow ?? effectiveRight)
        let eventDrive = min(eventLeft, eventRight)
        let progress = angleToProgress(drive)
        var rejectReason: LivePushupRejectReason?
        var currentRejectEventID: Int?
        var repCompleted = false
        var debugEvent = "phase=\(phaseName) L=\(fmt1(effectiveLeft)) R=\(fmt1(effectiveRight)) drive=\(fmt1(drive)) progress=\(Int((progress * 100).rounded()))%"

        let stanceKnee = [angles.leftKnee, angles.rightKnee].compactMap { $0 }.min()
        let legsExtended = stanceKnee.map { $0 >= minLegExtensionDeg } ?? true
        if !legsExtended {
            badStanceFrames += 1
            if badStanceFrames >= badStanceFramesForCondition {
                phase = .idleTop
                topReady = false
                resetCycle()
                return LivePushupCounterResult(
                    reps: reps,
                    progress: 0,
                    condition: .badStart,
                    leftElbowAngle: effectiveLeft,
                    rightElbowAngle: effectiveRight,
                    rejectReason: nil,
                    rejectEventID: nil,
                    isCycleActive: false,
                    lastRepAtMs: lastRepTs,
                    debugEvent: "Bad stance: knees are too bent for push-up tracking."
                )
            }
        } else {
            badStanceFrames = 0
        }

        switch phase {
        case .idleTop:
            if drive >= topThresholdDeg - topReadySlackDeg {
                topReady = true
            }

            let gapOk = timestampMs - lastCycleEndTs >= minInterRepGapMs
            let descending = prevDrive.map { ($0 - drive) >= minStartDropPerFrameDeg } ?? false
            if topReady && gapOk && drive <= topThresholdDeg - startCycleDeltaDeg && descending {
                startBelowThresholdFrames += 1
            } else {
                startBelowThresholdFrames = 0
            }

            if startBelowThresholdFrames >= 1 {
                phase = .descending
                cycleStartTs = timestampMs
                cycleStartAvg = drive
                cycleStartLeft = effectiveLeft
                cycleStartRight = effectiveRight
                cycleMinLeft = eventLeft
                cycleMinRight = eventRight
                cycleFrameCount = 1
                startBelowThresholdFrames = 0
                debugEvent = "Cycle started: top-to-bottom push-up motion armed."
            }

        case .descending:
            cycleFrameCount += 1
            cycleMinLeft = min(cycleMinLeft, eventLeft)
            cycleMinRight = min(cycleMinRight, eventRight)
            updateStartAsymmetryLatch(currentLeft: effectiveLeft, currentRight: effectiveRight)

            let reachedBottomByAbsolute = eventDrive <= bottomThresholdDeg
            let reachedBottomByTravel = cycleStartAvg - eventDrive >= minBottomTravelDeg
            if reachedBottomByAbsolute || reachedBottomByTravel {
                cycleReachedBottomByAbsolute = reachedBottomByAbsolute
                phase = .ascending
                debugEvent = reachedBottomByAbsolute ? "Bottom reached by elbow angle." : "Bottom reached by travel."
            } else if drive >= cycleStartAvg - 2 {
                if cycleStartedAsymmetric {
                    debugEvent = "Ignored: early left/right asymmetry."
                } else if attemptMaxTravel() >= minAttemptTravelForRejectDeg {
                    rejectReason = validateAttempt(timestampMs: timestampMs, reachedBottom: false)
                    currentRejectEventID = nextRejectEventIDIfNeeded(rejectReason)
                    if let rejectReason {
                        debugEvent = "Rejected before bottom: \(rejectReason.debugLabel)"
                    }
                }
                phase = .idleTop
                lastCycleEndTs = timestampMs
                topReady = drive >= topThresholdDeg - topReadySlackDeg
                resetCycle()
            }

        case .ascending:
            cycleFrameCount += 1
            cycleMinLeft = min(cycleMinLeft, eventLeft)
            cycleMinRight = min(cycleMinRight, eventRight)
            updateStartAsymmetryLatch(currentLeft: effectiveLeft, currentRight: effectiveRight)

            let returnedNearStart = drive >= cycleStartAvg - completionReturnSlackDeg
            if returnedNearStart {
                if cycleStartedAsymmetric {
                    debugEvent = "Ignored: early left/right asymmetry."
                } else if attemptMaxTravel() >= minAttemptTravelForRejectDeg {
                    let reject = validateAttempt(timestampMs: timestampMs, reachedBottom: true)
                    if let reject {
                        rejectReason = reject
                        currentRejectEventID = nextRejectEventIDIfNeeded(rejectReason)
                        debugEvent = "Rejected at top: \(reject.debugLabel)"
                    } else {
                        reps += 1
                        lastRepTs = timestampMs
                        repCompleted = true
                        debugEvent = "Clean rep counted."
                    }
                }
                phase = .idleTop
                lastCycleEndTs = timestampMs
                topReady = drive >= topThresholdDeg - topReadySlackDeg
                resetCycle()
            }
        }

        prevDrive = drive

        let condition: LivePushupCondition
        if repCompleted {
            condition = .repCounted
        } else if rejectReason == .insufficientTop || rejectReason == .asymmetricRange || rejectReason == .invalidBottomAngle {
            condition = .rangeTooSmall
        } else if !hasSeenValidPose {
            condition = .badStart
        } else {
            condition = .tracking
        }

        return LivePushupCounterResult(
            reps: reps,
            progress: progress,
            condition: condition,
            leftElbowAngle: effectiveLeft,
            rightElbowAngle: effectiveRight,
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
            badStanceFrames = 0
            prevDrive = nil
            startBelowThresholdFrames = 0
            resetCycle()
        }
    }

    private mutating func resetCycle() {
        cycleStartTs = 0
        cycleStartAvg = 0
        cycleStartLeft = 0
        cycleStartRight = 0
        cycleMinLeft = Double.greatestFiniteMagnitude
        cycleMinRight = Double.greatestFiniteMagnitude
        cycleFrameCount = 0
        cycleStartedAsymmetric = false
        cycleReachedBottomByAbsolute = false
    }

    private mutating func validateAttempt(timestampMs: Int64, reachedBottom: Bool) -> LivePushupRejectReason? {
        guard cycleMinLeft.isFinite, cycleMinRight.isFinite else {
            return .insufficientTop
        }

        if cycleFrameCount < minCycleFrames {
            return .tooFast
        }

        let durationMs = cycleStartTs > 0 ? timestampMs - cycleStartTs : Int64.max
        if durationMs > 0 && durationMs < minRepDurationMs {
            return .tooFast
        }

        let travelLeft = max(0, cycleStartLeft - cycleMinLeft)
        let travelRight = max(0, cycleStartRight - cycleMinRight)
        let highTravel = max(travelLeft, travelRight)
        let lowTravel = min(travelLeft, travelRight)

        if cycleMinLeft < minBottomElbowDeg || cycleMinRight < minBottomElbowDeg {
            return .invalidBottomAngle
        }

        if !reachedBottom || highTravel < minDepthTravelDeg {
            return .insufficientTop
        }

        let driveTravel = max(0, cycleStartAvg - min(cycleMinLeft, cycleMinRight))
        if !cycleReachedBottomByAbsolute && driveTravel < minBottomTravelDeg {
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
        max(max(0, cycleStartLeft - cycleMinLeft), max(0, cycleStartRight - cycleMinRight))
    }

    private mutating func updateStartAsymmetryLatch(currentLeft: Double, currentRight: Double) {
        guard !cycleStartedAsymmetric,
              cycleFrameCount > 0,
              cycleFrameCount <= startAsymmetryWindowFrames
        else {
            return
        }

        let travelLeft = max(0, cycleStartLeft - currentLeft)
        let travelRight = max(0, cycleStartRight - currentRight)
        let highTravel = max(travelLeft, travelRight)
        guard highTravel >= startAsymmetryTravelDeg else { return }

        let lowTravel = min(travelLeft, travelRight)
        let ratio = lowTravel / max(1, highTravel)
        if ratio < startAsymmetryMinRatio {
            cycleStartedAsymmetric = true
        }
    }

    private mutating func nextRejectEventIDIfNeeded(_ reason: LivePushupRejectReason?) -> Int? {
        guard reason != nil else { return nil }
        rejectEventID += 1
        return rejectEventID
    }

    private func angleToProgress(_ elbowAngle: Double) -> Double {
        let span = max(1, topThresholdDeg - bottomThresholdDeg)
        return ((elbowAngle - bottomThresholdDeg) / span).clamped(to: 0...1)
    }

    private func extractAngles(_ frame: LivePoseFrame) -> PushupAngles? {
        let leftElbow = angleDeg(
            frame.landmark(named: LivePoseLandmarkName.leftShoulder, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.leftElbow, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.leftWrist, minConfidence: landmarkMinConfidence)
        )
        let rightElbow = angleDeg(
            frame.landmark(named: LivePoseLandmarkName.rightShoulder, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.rightElbow, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.rightWrist, minConfidence: landmarkMinConfidence)
        )
        guard leftElbow != nil || rightElbow != nil else { return nil }

        let leftKnee = angleDeg(
            frame.landmark(named: LivePoseLandmarkName.leftHip, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.leftKnee, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.leftAnkle, minConfidence: landmarkMinConfidence)
        )
        let rightKnee = angleDeg(
            frame.landmark(named: LivePoseLandmarkName.rightHip, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.rightKnee, minConfidence: landmarkMinConfidence),
            frame.landmark(named: LivePoseLandmarkName.rightAnkle, minConfidence: landmarkMinConfidence)
        )

        return PushupAngles(
            leftElbow: leftElbow,
            rightElbow: rightElbow,
            leftKnee: leftKnee,
            rightKnee: rightKnee
        )
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
        guard let newValue else { return nil }
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

    private struct PushupAngles {
        let leftElbow: Double?
        let rightElbow: Double?
        let leftKnee: Double?
        let rightKnee: Double?
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
