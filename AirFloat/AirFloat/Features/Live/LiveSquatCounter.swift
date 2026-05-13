import Foundation
import os
@preconcurrency import Vision

enum LiveSquatCondition: Equatable {
    case badStart
    case tracking
    case repCounted
    case rangeTooSmall
    case trackingLost
}

enum LiveSquatRejectReason: Equatable {
    case trackingLost
    case insufficientTop
    case tooFast
    case asymmetricRange

    var missedAttemptDetail: String {
        switch self {
        case .trackingLost:
            return "Missed squat: tracking was lost."
        case .insufficientTop:
            return "Missed squat: depth was not low enough."
        case .tooFast:
            return "Missed squat: tempo was too fast."
        case .asymmetricRange:
            return "Missed squat: left/right depth mismatch."
        }
    }

    var notCountedHint: String {
        switch self {
        case .trackingLost:
            return "Not counted: tracking was lost."
        case .insufficientTop:
            return "Not counted: go deeper."
        case .tooFast:
            return "Not counted: movement is too fast."
        case .asymmetricRange:
            return "Not counted: left/right depth mismatch."
        }
    }

    var debugLabel: String {
        switch self {
        case .trackingLost:
            return "TRACKING_LOST"
        case .insufficientTop:
            return "INSUFFICIENT_DEPTH"
        case .tooFast:
            return "TOO_FAST"
        case .asymmetricRange:
            return "ASYMMETRIC_RANGE"
        }
    }
}

struct LiveSquatCounterResult: Equatable {
    let reps: Int
    let progress: Double
    let condition: LiveSquatCondition
    let leftKneeAngle: Double?
    let rightKneeAngle: Double?
    let rejectReason: LiveSquatRejectReason?
    let rejectEventID: Int?
    let isCycleActive: Bool
    let lastRepAtMs: Int64
    let debugEvent: String

    static let idle = LiveSquatCounterResult(
        reps: 0,
        progress: 0,
        condition: .badStart,
        leftKneeAngle: nil,
        rightKneeAngle: nil,
        rejectReason: nil,
        rejectEventID: nil,
        isCycleActive: false,
        lastRepAtMs: 0,
        debugEvent: "Waiting for Squat pose."
    )

    var title: String {
        switch condition {
        case .badStart:
            return "STAND TALL"
        case .tracking:
            return isCycleActive ? "SQUAT" : "READY"
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
        let angleText = [leftKneeAngle, rightKneeAngle]
            .compactMap { $0 }
            .map { "\(Int($0.rounded()))deg" }
            .joined(separator: " / ")

        switch condition {
        case .badStart:
            return "Stand tall with hips, knees, and ankles visible before starting."
        case .tracking:
            return angleText.isEmpty ? "\(reps) reps - \(progressText)" : "\(reps) reps - \(progressText) - \(angleText)"
        case .repCounted:
            return "\(reps) reps - clean squat detected."
        case .rangeTooSmall:
            if let rejectReason {
                return rejectReason.notCountedHint
            }
            return "\(reps) reps - go deeper before standing tall."
        case .trackingLost:
            return "Camera lost hips, knees, or ankles. Re-center and go again."
        }
    }
}

struct LiveSquatCounter {
    private enum Phase {
        case idleTop
        case descending
        case ascending
    }

    private let topThresholdDeg = 145.0
    private let bottomThresholdDeg = 100.0
    private let minRepDurationMs: Int64 = 400
    private let minDepthTravelDeg = 26.0
    private let minBottomTravelDeg = 40.0
    private let minBothSidesTravelDeg = 20.0
    private let minSymmetryRatio = 0.38
    private let minSymmetryBothTravelDeg = 30.0
    private let minAsymmetryCheckTravelDeg = 35.0
    private let emaAlpha = 0.35
    private let trackingLostFramesForCondition = 3
    private let minCycleFrames = 6
    private let minInterRepGapMs: Int64 = 320
    private let startCycleDeltaDeg = 8.0
    private let minStartDropPerFrameDeg = 0.6
    private let minTopReadyAngleDeg = 132.0
    private let topReadySlackDeg = 8.0
    private let startDebounceFrames = 2
    private let startAsymmetryWindowFrames = 4
    private let startAsymmetryTravelDeg = 20.0
    private let startAsymmetryMinRatio = 0.28
    private let landmarkMinConfidence: Float = 0.15
    private let logger = Logger(subsystem: "com.airfloat.AirFloat", category: "AirFloatTune")

    private var reps = 0
    private var phase: Phase = .idleTop
    private var emaLeft: Double?
    private var emaRight: Double?
    private var trackingGapFrames = 0
    private var hasSeenValidPose = false

    private var cycleStartTs: Int64 = 0
    private var cycleStartAvg = 0.0
    private var cycleStartLeft = 0.0
    private var cycleStartRight = 0.0
    private var cycleMinLeft = Double.greatestFiniteMagnitude
    private var cycleMinRight = Double.greatestFiniteMagnitude
    private var cycleFrameCount = 0
    private var lastCycleEndTs: Int64 = 0
    private var lastRepTs: Int64 = 0
    private var cycleStartedAsymmetric = false
    private var cycleReachedBottomByAbsolute = false
    private var prevDrive: Double?
    private var topReady = false
    private var startBelowThresholdFrames = 0
    private var rejectEventID = 0

    mutating func reset() {
        reps = 0
        phase = .idleTop
        emaLeft = nil
        emaRight = nil
        trackingGapFrames = 0
        hasSeenValidPose = false
        lastCycleEndTs = 0
        lastRepTs = 0
        cycleStartedAsymmetric = false
        prevDrive = nil
        topReady = false
        startBelowThresholdFrames = 0
        rejectEventID = 0
        resetCycle()
    }

    mutating func update(frame: LivePoseFrame, timestampMs: Int64) -> LiveSquatCounterResult {
        guard let angles = extractKneeAngles(frame) else {
            onTrackingGap()
            return LiveSquatCounterResult(
                reps: reps,
                progress: 0,
                condition: trackingGapFrames >= trackingLostFramesForCondition ? .trackingLost : .badStart,
                leftKneeAngle: nil,
                rightKneeAngle: nil,
                rejectReason: nil,
                rejectEventID: nil,
                isCycleActive: false,
                lastRepAtMs: lastRepTs,
                debugEvent: trackingGapFrames >= trackingLostFramesForCondition
                    ? "Tracking gap: hips/knees/ankles dropped."
                    : "Waiting for hips, knees, and ankles."
            )
        }

        trackingGapFrames = 0
        hasSeenValidPose = true

        let left = ema(previous: emaLeft, newValue: angles.left)
        let right = ema(previous: emaRight, newValue: angles.right)
        emaLeft = left
        emaRight = right

        let drive = min(left, right)
        let eventLeft = min(left, angles.left)
        let eventRight = min(right, angles.right)
        let eventDrive = min(eventLeft, eventRight)
        let progress = angleToProgress(drive)
        var rejectReason: LiveSquatRejectReason?
        var currentRejectEventID: Int?
        var repCompleted = false
        var debugEvent = "phase=\(phaseName) L=\(fmt1(left)) R=\(fmt1(right)) drive=\(fmt1(drive)) progress=\(Int((progress * 100).rounded()))%"

        switch phase {
        case .idleTop:
            if drive >= minTopReadyAngleDeg {
                topReady = true
            }

            let gapOk = timestampMs - lastCycleEndTs >= minInterRepGapMs
            let descending = prevDrive.map { ($0 - drive) >= minStartDropPerFrameDeg } ?? false
            let nearTop = drive >= (minTopReadyAngleDeg - topReadySlackDeg)
            let canStart =
                topReady &&
                gapOk &&
                descending &&
                drive <= topThresholdDeg - startCycleDeltaDeg

            if canStart {
                startBelowThresholdFrames += 1
            } else if nearTop {
                startBelowThresholdFrames = 0
            } else {
                startBelowThresholdFrames = 0
            }

            if startBelowThresholdFrames >= startDebounceFrames {
                phase = .descending
                cycleStartTs = timestampMs
                cycleStartAvg = drive
                cycleStartLeft = left
                cycleStartRight = right
                cycleMinLeft = eventLeft
                cycleMinRight = eventRight
                cycleFrameCount = 1
                startBelowThresholdFrames = 0
                debugEvent = "Cycle started: stand-to-squat motion armed."
                logCycleStarted(timestampMs: timestampMs, left: left, right: right, drive: drive)
            }

        case .descending:
            cycleFrameCount += 1
            cycleMinLeft = min(cycleMinLeft, eventLeft)
            cycleMinRight = min(cycleMinRight, eventRight)
            updateStartAsymmetryLatch(currentLeft: left, currentRight: right)

            let reachedBottomByAbsolute = eventDrive <= bottomThresholdDeg
            let reachedBottomByTravel = (cycleStartAvg - eventDrive) >= minBottomTravelDeg
            if reachedBottomByAbsolute || reachedBottomByTravel {
                cycleReachedBottomByAbsolute = reachedBottomByAbsolute
                phase = .ascending
                debugEvent = reachedBottomByAbsolute ? "Bottom reached by knee angle." : "Bottom reached by travel."
                logBottomReached(
                    timestampMs: timestampMs,
                    left: left,
                    right: right,
                    drive: drive,
                    byAbsolute: reachedBottomByAbsolute
                )
            } else if drive >= cycleStartAvg - 2 {
                if cycleStartedAsymmetric {
                    debugEvent = "Ignored: early left/right asymmetry."
                    logCycleIgnored(reason: "EARLY_ASYMMETRY")
                } else {
                    rejectReason = validateAttempt(timestampMs: timestampMs, reachedBottom: false)
                    currentRejectEventID = nextRejectEventIDIfNeeded(rejectReason)
                    if let rejectReason {
                        debugEvent = "Rejected before bottom: \(rejectReason.debugLabel)"
                    }
                }
                phase = .idleTop
                lastCycleEndTs = timestampMs
                topReady = drive >= minTopReadyAngleDeg
                resetCycle()
            }

        case .ascending:
            cycleFrameCount += 1
            cycleMinLeft = min(cycleMinLeft, eventLeft)
            cycleMinRight = min(cycleMinRight, eventRight)
            updateStartAsymmetryLatch(currentLeft: left, currentRight: right)

            let returnedNearStart = drive >= (cycleStartAvg - 2)
            if returnedNearStart {
                if cycleStartedAsymmetric {
                    debugEvent = "Ignored: early left/right asymmetry."
                    logCycleIgnored(reason: "EARLY_ASYMMETRY")
                } else {
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
                        logRep(timestampMs: timestampMs)
                    }
                }
                phase = .idleTop
                lastCycleEndTs = timestampMs
                topReady = drive >= minTopReadyAngleDeg
                resetCycle()
            }
        }

        prevDrive = drive

        let condition: LiveSquatCondition
        if repCompleted {
            condition = .repCounted
        } else if rejectReason == .insufficientTop {
            condition = .rangeTooSmall
        } else if !hasSeenValidPose {
            condition = .badStart
        } else {
            condition = .tracking
        }

        return LiveSquatCounterResult(
            reps: reps,
            progress: progress,
            condition: condition,
            leftKneeAngle: left,
            rightKneeAngle: right,
            rejectReason: rejectReason,
            rejectEventID: currentRejectEventID,
            isCycleActive: phase != .idleTop,
            lastRepAtMs: lastRepTs,
            debugEvent: debugEvent
        )
    }

    private mutating func onTrackingGap() {
        trackingGapFrames += 1
        if phase != .idleTop || trackingGapFrames == trackingLostFramesForCondition {
            let gapFrames = trackingGapFrames
            let phaseName = phaseName
            printTune("squat trackingGap frames=\(gapFrames) phase=\(phaseName)")
            logger.info(
                "squat trackingGap frames=\(gapFrames, privacy: .public) phase=\(phaseName, privacy: .public)"
            )
        }
        phase = .idleTop
        prevDrive = nil
        topReady = false
        startBelowThresholdFrames = 0
        resetCycle()
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

    private mutating func nextRejectEventIDIfNeeded(_ reason: LiveSquatRejectReason?) -> Int? {
        guard reason != nil else { return nil }
        rejectEventID += 1
        return rejectEventID
    }

    private func validateAttempt(timestampMs: Int64, reachedBottom: Bool) -> LiveSquatRejectReason? {
        guard cycleMinLeft.isFinite, cycleMinRight.isFinite else {
            logRejected(reason: "TRACKING_LOST")
            return .trackingLost
        }

        if cycleFrameCount < minCycleFrames {
            printTune("squat repRejected reason=TOO_FAST frames=\(cycleFrameCount) minFrames=\(minCycleFrames)")
            logger.info(
                "squat repRejected reason=TOO_FAST frames=\(self.cycleFrameCount, privacy: .public) minFrames=\(self.minCycleFrames, privacy: .public)"
            )
            return .tooFast
        }

        let durationMs = cycleStartTs > 0 ? timestampMs - cycleStartTs : Int64.max
        if durationMs > 0, durationMs < minRepDurationMs {
            printTune("squat repRejected reason=TOO_FAST durationMs=\(durationMs) minMs=\(minRepDurationMs)")
            logger.info(
                "squat repRejected reason=TOO_FAST durationMs=\(durationMs, privacy: .public) minMs=\(self.minRepDurationMs, privacy: .public)"
            )
            return .tooFast
        }

        let travelLeft = max(0, cycleStartLeft - cycleMinLeft)
        let travelRight = max(0, cycleStartRight - cycleMinRight)
        let high = max(travelLeft, travelRight)
        let low = min(travelLeft, travelRight)

        if !reachedBottom || high < minDepthTravelDeg {
            printTune("squat repRejected reason=INSUFFICIENT_DEPTH travelL=\(fmt1(travelLeft)) travelR=\(fmt1(travelRight)) minDepth=\(fmt1(minDepthTravelDeg)) reachedBottom=\(reachedBottom)")
            logger.info(
                "squat repRejected reason=INSUFFICIENT_DEPTH travelL=\(self.fmt1(travelLeft), privacy: .public) travelR=\(self.fmt1(travelRight), privacy: .public) minDepth=\(self.fmt1(self.minDepthTravelDeg), privacy: .public) reachedBottom=\(reachedBottom, privacy: .public)"
            )
            return .insufficientTop
        }

        let driveTravel = max(0, cycleStartAvg - min(cycleMinLeft, cycleMinRight))
        if !cycleReachedBottomByAbsolute, driveTravel < minBottomTravelDeg {
            printTune("squat repRejected reason=INSUFFICIENT_DEPTH driveTravel=\(fmt1(driveTravel)) minTravelBottom=\(fmt1(minBottomTravelDeg)) reachedBottomByAbs=false")
            logger.info(
                "squat repRejected reason=INSUFFICIENT_DEPTH driveTravel=\(self.fmt1(driveTravel), privacy: .public) minTravelBottom=\(self.fmt1(self.minBottomTravelDeg), privacy: .public) reachedBottomByAbs=false"
            )
            return .insufficientTop
        }

        if low < minBothSidesTravelDeg {
            printTune("squat repRejected reason=ASYMMETRIC_RANGE travelL=\(fmt1(travelLeft)) travelR=\(fmt1(travelRight)) minBoth=\(fmt1(minBothSidesTravelDeg))")
            logger.info(
                "squat repRejected reason=ASYMMETRIC_RANGE travelL=\(self.fmt1(travelLeft), privacy: .public) travelR=\(self.fmt1(travelRight), privacy: .public) minBoth=\(self.fmt1(self.minBothSidesTravelDeg), privacy: .public)"
            )
            return .asymmetricRange
        }

        let ratio = low / max(1, high)
        let minTravelForAsymmetry = max(minDepthTravelDeg, minSymmetryBothTravelDeg)
        if high >= minAsymmetryCheckTravelDeg,
           low >= minTravelForAsymmetry,
           ratio < minSymmetryRatio
        {
            printTune("squat repRejected reason=ASYMMETRIC_RANGE travelL=\(fmt1(travelLeft)) travelR=\(fmt1(travelRight)) ratio=\(fmt2(ratio)) minRatio=\(fmt2(minSymmetryRatio))")
            logger.info(
                "squat repRejected reason=ASYMMETRIC_RANGE travelL=\(self.fmt1(travelLeft), privacy: .public) travelR=\(self.fmt1(travelRight), privacy: .public) ratio=\(self.fmt2(ratio), privacy: .public) minRatio=\(self.fmt2(self.minSymmetryRatio), privacy: .public)"
            )
            return .asymmetricRange
        }

        return nil
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
        let high = max(travelLeft, travelRight)
        guard high >= startAsymmetryTravelDeg else { return }

        let low = min(travelLeft, travelRight)
        let ratio = low / max(1, high)
        if ratio < startAsymmetryMinRatio {
            cycleStartedAsymmetric = true
            let travelLeftText = fmt1(travelLeft)
            let travelRightText = fmt1(travelRight)
            let ratioText = fmt2(ratio)
            let frameCount = cycleFrameCount
            printTune("squat earlyAsymmetry latched travelL=\(travelLeftText) travelR=\(travelRightText) ratio=\(ratioText) frames=\(frameCount)")
            logger.info(
                "squat earlyAsymmetry latched travelL=\(travelLeftText, privacy: .public) travelR=\(travelRightText, privacy: .public) ratio=\(ratioText, privacy: .public) frames=\(frameCount, privacy: .public)"
            )
        }
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

    private func logCycleStarted(timestampMs: Int64, left: Double, right: Double, drive: Double) {
        let message = "squat cycleStarted ts=\(timestampMs) left=\(fmt1(left)) right=\(fmt1(right)) drive=\(fmt1(drive))"
        printTune(message)
        logger.info(
            "squat cycleStarted ts=\(timestampMs, privacy: .public) left=\(self.fmt1(left), privacy: .public) right=\(self.fmt1(right), privacy: .public) drive=\(self.fmt1(drive), privacy: .public)"
        )
    }

    private func logBottomReached(timestampMs: Int64, left: Double, right: Double, drive: Double, byAbsolute: Bool) {
        let message = "squat bottomReached ts=\(timestampMs) left=\(fmt1(left)) right=\(fmt1(right)) drive=\(fmt1(drive)) byAbsolute=\(byAbsolute)"
        printTune(message)
        logger.info(
            "squat bottomReached ts=\(timestampMs, privacy: .public) left=\(self.fmt1(left), privacy: .public) right=\(self.fmt1(right), privacy: .public) drive=\(self.fmt1(drive), privacy: .public) byAbsolute=\(byAbsolute, privacy: .public)"
        )
    }

    private func logCycleIgnored(reason: String) {
        let travelLeft = max(0, cycleStartLeft - cycleMinLeft)
        let travelRight = max(0, cycleStartRight - cycleMinRight)
        let message = "squat cycleIgnored reason=\(reason) travelL=\(fmt1(travelLeft)) travelR=\(fmt1(travelRight))"
        printTune(message)
        logger.info(
            "squat cycleIgnored reason=\(reason, privacy: .public) travelL=\(self.fmt1(travelLeft), privacy: .public) travelR=\(self.fmt1(travelRight), privacy: .public)"
        )
    }

    private func logRejected(reason: String) {
        printTune("squat repRejected reason=\(reason)")
        logger.info("squat repRejected reason=\(reason, privacy: .public)")
    }

    private func logRep(timestampMs: Int64) {
        let ampLeft = cycleStartLeft - cycleMinLeft
        let ampRight = cycleStartRight - cycleMinRight
        let message = "squat rep=\(reps) ts=\(timestampMs) minL=\(fmt1(cycleMinLeft)) maxL=\(fmt1(cycleStartLeft)) ampL=\(fmt1(ampLeft)) minR=\(fmt1(cycleMinRight)) maxR=\(fmt1(cycleStartRight)) ampR=\(fmt1(ampRight))"
        printTune(message)
        logger.info(
            "squat rep=\(self.reps, privacy: .public) ts=\(timestampMs, privacy: .public) minL=\(self.fmt1(self.cycleMinLeft), privacy: .public) maxL=\(self.fmt1(self.cycleStartLeft), privacy: .public) ampL=\(self.fmt1(ampLeft), privacy: .public) minR=\(self.fmt1(self.cycleMinRight), privacy: .public) maxR=\(self.fmt1(self.cycleStartRight), privacy: .public) ampR=\(self.fmt1(ampRight), privacy: .public)"
        )
    }

    private func printTune(_ message: String) {
        #if DEBUG
        print("[AirFloatTune] \(message)")
        #endif
    }

    private func fmt1(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func fmt2(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func angleToProgress(_ kneeAngle: Double) -> Double {
        let span = max(1, topThresholdDeg - bottomThresholdDeg)
        return min(1, max(0, (topThresholdDeg - kneeAngle) / span))
    }

    private func extractKneeAngles(_ frame: LivePoseFrame) -> (left: Double, right: Double)? {
        guard let leftHip = frame.landmark(.leftHip, minConfidence: landmarkMinConfidence),
              let leftKnee = frame.landmark(.leftKnee, minConfidence: landmarkMinConfidence),
              let leftAnkle = frame.landmark(.leftAnkle, minConfidence: landmarkMinConfidence),
              let rightHip = frame.landmark(.rightHip, minConfidence: landmarkMinConfidence),
              let rightKnee = frame.landmark(.rightKnee, minConfidence: landmarkMinConfidence),
              let rightAnkle = frame.landmark(.rightAnkle, minConfidence: landmarkMinConfidence)
        else {
            return nil
        }

        return (
            left: angle(a: leftHip, b: leftKnee, c: leftAnkle),
            right: angle(a: rightHip, b: rightKnee, c: rightAnkle)
        )
    }

    private func angle(a: LivePoseLandmark, b: LivePoseLandmark, c: LivePoseLandmark) -> Double {
        let ab = (x: a.x - b.x, y: a.y - b.y)
        let cb = (x: c.x - b.x, y: c.y - b.y)
        let dot = ab.x * cb.x + ab.y * cb.y
        let abLength = sqrt(ab.x * ab.x + ab.y * ab.y)
        let cbLength = sqrt(cb.x * cb.x + cb.y * cb.y)
        guard abLength > 0, cbLength > 0 else { return 0 }

        let cosine = min(1, max(-1, dot / (abLength * cbLength)))
        return acos(cosine) * 180 / .pi
    }

    private func ema(previous: Double?, newValue: Double) -> Double {
        guard let previous else { return newValue }
        return emaAlpha * newValue + (1 - emaAlpha) * previous
    }
}
