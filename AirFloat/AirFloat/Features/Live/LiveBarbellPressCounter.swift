import Foundation
@preconcurrency import Vision

enum LiveBarbellPressCondition: Equatable {
    case waitingForPose
    case badStart
    case tracking
    case repCounted
    case rangeTooSmall
    case trackingLost
}

enum LiveBarbellPressRejectReason: Equatable {
    case invalidBottomAngle
    case insufficientTop
    case tooFast
    case asymmetricRange

    var missedAttemptDetail: String {
        switch self {
        case .invalidBottomAngle:
            return "Missed rep: unstable bottom position."
        case .insufficientTop:
            return "Missed rep: lockout was not high enough."
        case .tooFast:
            return "Missed rep: tempo was too fast."
        case .asymmetricRange:
            return "Missed rep: left/right range drifted."
        }
    }

    var notCountedHint: String {
        switch self {
        case .invalidBottomAngle:
            return "Not counted: unstable bottom position."
        case .insufficientTop:
            return "Not counted: raise higher at the top."
        case .tooFast:
            return "Not counted: movement is too fast."
        case .asymmetricRange:
            return "Not counted: left/right range mismatch."
        }
    }
}

struct LiveBarbellPressCounterResult: Equatable {
    let reps: Int
    let progress: Double
    let condition: LiveBarbellPressCondition
    let leftAngle: Double?
    let rightAngle: Double?
    let rejectReason: LiveBarbellPressRejectReason?
    let rejectEventID: Int?

    static let idle = LiveBarbellPressCounterResult(
        reps: 0,
        progress: 0,
        condition: .waitingForPose,
        leftAngle: nil,
        rightAngle: nil,
        rejectReason: nil,
        rejectEventID: nil
    )

    var title: String {
        switch condition {
        case .waitingForPose:
            return "GET READY"
        case .badStart:
            return "RAISE ARMS"
        case .tracking:
            return "TRACKING"
        case .repCounted:
            return "CLEAN REP"
        case .rangeTooSmall:
            return "RANGE TOO SMALL"
        case .trackingLost:
            return "TRACK LOST"
        }
    }

    var detail: String {
        let progressText = "\(Int((progress * 100).rounded()))% ARC"
        let angleText = [leftAngle, rightAngle]
            .compactMap { $0 }
            .map { "\(Int($0.rounded()))deg" }
            .joined(separator: " / ")

        switch condition {
        case .waitingForPose:
            return "Step back until head, shoulders, elbows, and wrists stay visible. Bright side light helps; avoid cropping your hands."
        case .badStart:
            return "Raise both hands above the shoulder line to arm the counter."
        case .tracking:
            return angleText.isEmpty ? "\(reps) reps · \(progressText)" : "\(reps) reps · \(progressText) · \(angleText)"
        case .repCounted:
            return "\(reps) reps · clean upstroke detected."
        case .rangeTooSmall:
            if let rejectReason {
                return rejectReason.notCountedHint
            }
            return "\(reps) reps · move through a larger press arc before locking out."
        case .trackingLost:
            return "Camera lost the line. Re-center and go again."
        }
    }
}

struct LiveBarbellPressCounter {
    private struct AngleFSM {
        private enum State {
            case needInitialUp
            case waitingForDown
            case waitingForUp
        }

        private var state: State = .needInitialUp
        private var hold = 0
        let down: Double
        let up: Double
        let holdFrames: Int

        init(down: Double, up: Double, holdFrames: Int) {
            self.down = down
            self.up = up
            self.holdFrames = holdFrames
        }

        var isPrimed: Bool {
            state != .needInitialUp
        }

        mutating func reset() {
            state = .needInitialUp
            hold = 0
        }

        mutating func update(_ angle: Double?) -> Bool {
            guard let angle else { return false }

            switch state {
            case .needInitialUp:
                if angle > up {
                    state = .waitingForDown
                    hold = 0
                }
            case .waitingForDown:
                if angle < down {
                    state = .waitingForUp
                    hold = 0
                }
            case .waitingForUp:
                if angle > up {
                    hold += 1
                    let requiredHold = max(1, holdFrames)
                    if hold >= requiredHold {
                        state = .waitingForDown
                        hold = 0
                        return true
                    }
                } else if angle < down {
                    hold = 0
                }
            }

            return false
        }
    }

    private var fsmL = AngleFSM(down: 82, up: 128, holdFrames: 2)
    private var fsmR = AngleFSM(down: 82, up: 128, holdFrames: 2)
    private var reps = 0

    private let downThreshold = 82.0
    private let upThreshold = 128.0
    private let gaugeBottomAngleDeg = 82.0
    private let syncWindowFrames = 10
    private let emaAlpha = 0.35
    private let fastEmaAlpha = 0.78
    private let minRepBottomAngleDeg = 35.0
    private let minUnderTopTravelDeg = 16.5
    private let minRepDurationMs: Int64 = 420
    private let minRangeSymmetryRatio = 0.55
    private let landmarkMinConfidence: Float = 0.15
    private let armsDownWristOffset = 0.14

    private var emaL: Double?
    private var emaR: Double?
    private var fastL: Double?
    private var fastR: Double?
    private var pendingL = 0
    private var pendingR = 0
    private var trackingGapFrames = 0
    private let trackingLostFramesForCondition = 3
    private let resetStateAfterGapFrames = 4
    private var repMinL = Double.greatestFiniteMagnitude
    private var repMaxL = -Double.greatestFiniteMagnitude
    private var repMinR = Double.greatestFiniteMagnitude
    private var repMaxR = -Double.greatestFiniteMagnitude
    private var repRangeStartTs: Int64 = 0
    private var rangeMinL = Double.greatestFiniteMagnitude
    private var rangeMaxL = -Double.greatestFiniteMagnitude
    private var rangeMinR = Double.greatestFiniteMagnitude
    private var rangeMaxR = -Double.greatestFiniteMagnitude
    private var rangeEvalFrames = 0
    private var rangeTooSmallWindowStreak = 0
    private var rejectEventID = 0

    mutating func reset() {
        fsmL.reset()
        fsmR.reset()
        reps = 0
        emaL = nil
        emaR = nil
        fastL = nil
        fastR = nil
        pendingL = 0
        pendingR = 0
        trackingGapFrames = 0
        resetRepRange()
        resetRangeEval()
        rejectEventID = 0
    }

    mutating func update(frame: LivePoseFrame, timestampMs: Int64) -> LiveBarbellPressCounterResult {
        guard hasRequiredPressPoints(frame), !areArmsDown(frame) else {
            return onTrackingGap(timestampMs: timestampMs)
        }

        let leftAngle = elbowAngle(
            shoulder: .leftShoulder,
            elbow: .leftElbow,
            wrist: .leftWrist,
            frame: frame
        )
        let rightAngle = elbowAngle(
            shoulder: .rightShoulder,
            elbow: .rightElbow,
            wrist: .rightWrist,
            frame: frame
        )
        guard let leftAngle = sanitizeAngle(leftAngle),
              let rightAngle = sanitizeAngle(rightAngle)
        else {
            return onTrackingGap(timestampMs: timestampMs)
        }

        trackingGapFrames = 0
        emaL = ema(previous: emaL, newValue: leftAngle)
        emaR = ema(previous: emaR, newValue: rightAngle)
        let smoothL = emaL ?? leftAngle
        let smoothR = emaR ?? rightAngle
        fastL = ema(previous: fastL, newValue: leftAngle, alpha: fastEmaAlpha)
        fastR = ema(previous: fastR, newValue: rightAngle, alpha: fastEmaAlpha)
        let eventL = fastL ?? leftAngle
        let eventR = fastR ?? rightAngle

        let leftRep = fsmL.update(eventL)
        let rightRep = fsmR.update(eventR)
        let bothPrimed = fsmL.isPrimed && fsmR.isPrimed
        updateRepRange(left: eventL, right: eventR, timestampMs: timestampMs)

        if leftRep { pendingL = syncWindowFrames }
        if rightRep { pendingR = syncWindowFrames }

        var condition: LiveBarbellPressCondition
        var rejectReason: LiveBarbellPressRejectReason?
        var currentRejectEventID: Int?
        if bothPrimed, pendingL > 0, pendingR > 0 {
            if let reason = validateCurrentRep(timestampMs: timestampMs) {
                rejectEventID += 1
                rejectReason = reason
                currentRejectEventID = rejectEventID
                condition = .rangeTooSmall
            } else {
                reps += 1
                condition = .repCounted
            }
            pendingL = 0
            pendingR = 0
            resetRepRange()
            resetRangeEval()
        } else {
            if pendingL > 0 { pendingL -= 1 }
            if pendingR > 0 { pendingR -= 1 }
            condition = bothPrimed ? (isRangeTooSmall(left: eventL, right: eventR) ? .rangeTooSmall : .tracking) : .badStart
        }

        if !bothPrimed {
            pendingL = 0
            pendingR = 0
            resetRepRange()
            resetRangeEval()
        }

        return LiveBarbellPressCounterResult(
            reps: reps,
            progress: progress(left: smoothL, right: smoothR),
            condition: condition,
            leftAngle: smoothL,
            rightAngle: smoothR,
            rejectReason: rejectReason,
            rejectEventID: currentRejectEventID
        )
    }

    private mutating func onTrackingGap(timestampMs: Int64) -> LiveBarbellPressCounterResult {
        pendingL = 0
        pendingR = 0
        resetRepRange()
        resetRangeEval()
        trackingGapFrames += 1
        if trackingGapFrames == resetStateAfterGapFrames {
            fsmL.reset()
            fsmR.reset()
            emaL = nil
            emaR = nil
            fastL = nil
            fastR = nil
        }

        return LiveBarbellPressCounterResult(
            reps: reps,
            progress: 0,
            condition: trackingGapFrames >= trackingLostFramesForCondition ? .trackingLost : .waitingForPose,
            leftAngle: nil,
            rightAngle: nil,
            rejectReason: nil,
            rejectEventID: nil
        )
    }

    private func elbowAngle(
        shoulder: VNHumanBodyPoseObservation.JointName,
        elbow: VNHumanBodyPoseObservation.JointName,
        wrist: VNHumanBodyPoseObservation.JointName,
        frame: LivePoseFrame
    ) -> Double? {
        guard let shoulder = frame.landmark(shoulder, minConfidence: landmarkMinConfidence),
              let elbow = frame.landmark(elbow, minConfidence: landmarkMinConfidence),
              let wrist = frame.landmark(wrist, minConfidence: landmarkMinConfidence)
        else {
            return nil
        }

        return angle(a: shoulder, b: elbow, c: wrist)
    }

    private func angle(a: LivePoseLandmark, b: LivePoseLandmark, c: LivePoseLandmark) -> Double {
        let ab = (x: a.x - b.x, y: a.y - b.y)
        let cb = (x: c.x - b.x, y: c.y - b.y)
        let dot = ab.x * cb.x + ab.y * cb.y
        let abLength = sqrt(ab.x * ab.x + ab.y * ab.y)
        let cbLength = sqrt(cb.x * cb.x + cb.y * cb.y)
        guard abLength > 0, cbLength > 0 else { return 0 }

        let cosine = (dot / (abLength * cbLength)).clamped(to: -1...1)
        return acos(cosine) * 180 / .pi
    }

    private func progress(left: Double?, right: Double?) -> Double {
        min(angleProgress(left), angleProgress(right))
    }

    private func angleProgress(_ angle: Double?) -> Double {
        guard let angle else { return 0 }
        let lower = min(gaugeBottomAngleDeg, upThreshold - 1)
        let span = max(1, upThreshold - lower)
        return ((angle - lower) / span).clamped(to: 0...1)
    }

    private func sanitizeAngle(_ angle: Double?) -> Double? {
        guard let angle, angle >= 5, angle <= 179 else { return nil }
        return angle
    }

    private func ema(previous: Double?, newValue: Double, alpha: Double? = nil) -> Double {
        guard let previous else { return newValue }
        let alpha = alpha ?? emaAlpha
        return alpha * newValue + (1 - alpha) * previous
    }

    private mutating func updateRepRange(left: Double, right: Double, timestampMs: Int64) {
        if repRangeStartTs == 0 {
            repRangeStartTs = timestampMs
        }
        repMinL = min(repMinL, left)
        repMaxL = max(repMaxL, left)
        repMinR = min(repMinR, right)
        repMaxR = max(repMaxR, right)
    }

    private mutating func resetRepRange() {
        repMinL = Double.greatestFiniteMagnitude
        repMaxL = -Double.greatestFiniteMagnitude
        repMinR = Double.greatestFiniteMagnitude
        repMaxR = -Double.greatestFiniteMagnitude
        repRangeStartTs = 0
    }

    private func validateCurrentRep(timestampMs: Int64) -> LiveBarbellPressRejectReason? {
        guard repMinL.isFinite, repMaxL.isFinite, repMinR.isFinite, repMaxR.isFinite else {
            return .invalidBottomAngle
        }
        if repMinL < minRepBottomAngleDeg || repMinR < minRepBottomAngleDeg {
            return .invalidBottomAngle
        }
        let durationMs = repRangeStartTs > 0 ? timestampMs - repRangeStartTs : Int64.max
        if durationMs > 0, durationMs < minRepDurationMs {
            return .tooFast
        }
        let ampL = max(0, repMaxL - repMinL)
        let ampR = max(0, repMaxR - repMinR)
        let high = max(ampL, ampR)
        let low = min(ampL, ampR)
        if high < minUnderTopTravelDeg {
            return .insufficientTop
        }
        if low / max(1, high) < minRangeSymmetryRatio {
            return .asymmetricRange
        }
        return nil
    }

    private mutating func isRangeTooSmall(left: Double, right: Double) -> Bool {
        updateRangeEval(left: left, right: right)
        if rangeEvalFrames < 16 { return false }
        let ampL = rangeMaxL - rangeMinL
        let ampR = rangeMaxR - rangeMinR
        let tooSmall = ampL < 20 || ampR < 20
        rangeTooSmallWindowStreak = tooSmall ? rangeTooSmallWindowStreak + 1 : 0
        rangeEvalFrames = 1
        rangeMinL = left
        rangeMaxL = left
        rangeMinR = right
        rangeMaxR = right
        return rangeTooSmallWindowStreak >= 2
    }

    private mutating func updateRangeEval(left: Double, right: Double) {
        if rangeEvalFrames == 0 {
            rangeEvalFrames = 1
            rangeMinL = left
            rangeMaxL = left
            rangeMinR = right
            rangeMaxR = right
            return
        }
        rangeEvalFrames += 1
        rangeMinL = min(rangeMinL, left)
        rangeMaxL = max(rangeMaxL, left)
        rangeMinR = min(rangeMinR, right)
        rangeMaxR = max(rangeMaxR, right)
    }

    private mutating func resetRangeEval() {
        rangeEvalFrames = 0
        rangeMinL = Double.greatestFiniteMagnitude
        rangeMaxL = -Double.greatestFiniteMagnitude
        rangeMinR = Double.greatestFiniteMagnitude
        rangeMaxR = -Double.greatestFiniteMagnitude
        rangeTooSmallWindowStreak = 0
    }

    private func hasRequiredPressPoints(_ frame: LivePoseFrame) -> Bool {
        [
            VNHumanBodyPoseObservation.JointName.leftShoulder,
            .leftElbow,
            .leftWrist,
            .rightShoulder,
            .rightElbow,
            .rightWrist,
        ].allSatisfy { frame.landmark($0, minConfidence: landmarkMinConfidence) != nil }
    }

    private func areArmsDown(_ frame: LivePoseFrame) -> Bool {
        guard let leftShoulder = frame.landmark(.leftShoulder, minConfidence: landmarkMinConfidence),
              let leftWrist = frame.landmark(.leftWrist, minConfidence: landmarkMinConfidence),
              let rightShoulder = frame.landmark(.rightShoulder, minConfidence: landmarkMinConfidence),
              let rightWrist = frame.landmark(.rightWrist, minConfidence: landmarkMinConfidence)
        else {
            return false
        }

        return (leftWrist.y - leftShoulder.y) > armsDownWristOffset &&
            (rightWrist.y - rightShoulder.y) > armsDownWristOffset
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
