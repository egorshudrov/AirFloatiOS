import Foundation

struct LiveSessionState: Equatable {
    private(set) var startedAtMs: Int64?
    private(set) var reps = 0
    private(set) var successfulAttempts = 0
    private(set) var failedAttempts = 0
    private(set) var estimatedKcal = 0.0
    private(set) var attempts: [WorkoutSessionAttemptRecord] = []

    var hasActivity: Bool {
        reps > 0 || !attempts.isEmpty
    }

    var attemptCount: Int {
        successfulAttempts + failedAttempts
    }

    var completionRate: Int {
        guard attemptCount > 0 else { return 0 }
        return Int((Double(successfulAttempts) * 100.0) / Double(attemptCount))
            .clamped(to: 0...100)
    }

    mutating func startIfNeeded(at timestampMs: Int64) {
        if startedAtMs == nil {
            startedAtMs = timestampMs
        }
    }

    mutating func reset() {
        startedAtMs = nil
        reps = 0
        successfulAttempts = 0
        failedAttempts = 0
        estimatedKcal = 0.0
        attempts = []
    }

    mutating func recordAttempt(
        success: Bool,
        repSnapshot: Int,
        elapsedMs: Int64,
        estimatedKcal: Double,
        detail: String
    ) {
        if success {
            successfulAttempts += 1
            reps = max(reps, repSnapshot)
        } else {
            failedAttempts += 1
        }

        self.estimatedKcal = max(self.estimatedKcal, estimatedKcal)
        attempts.append(
            WorkoutSessionAttemptRecord(
                index: attempts.count + 1,
                repSnapshot: repSnapshot,
                success: success,
                elapsedMs: elapsedMs,
                estimatedKcal: estimatedKcal,
                detail: detail
            )
        )
    }

    mutating func recordCleanRepIfNeeded(
        reps liveReps: Int,
        nowMs: Int64,
        kcalPerRep: Double = 0.6
    ) {
        guard liveReps > reps else { return }
        let startedAtMs = startedAtMs ?? nowMs

        for rep in (reps + 1)...liveReps {
            let elapsedMs = max(1_000, nowMs - startedAtMs)
            recordAttempt(
                success: true,
                repSnapshot: rep,
                elapsedMs: elapsedMs,
                estimatedKcal: Double(rep) * kcalPerRep,
                detail: "Live MediaPipe Barbell Press clean rep counted from camera tracking."
            )
        }
    }

    mutating func recordCleanRepIfNeeded(
        reps liveReps: Int,
        nowMs: Int64,
        kcalPerRep: Double = 0.6,
        detail: String
    ) {
        guard liveReps > reps else { return }
        let startedAtMs = startedAtMs ?? nowMs

        for rep in (reps + 1)...liveReps {
            let elapsedMs = max(1_000, nowMs - startedAtMs)
            recordAttempt(
                success: true,
                repSnapshot: rep,
                elapsedMs: elapsedMs,
                estimatedKcal: Double(rep) * kcalPerRep,
                detail: detail
            )
        }
    }

    mutating func recordRejectedRep(
        reason: LiveBarbellPressRejectReason,
        repSnapshot: Int,
        nowMs: Int64,
        kcalPerAttempt: Double = 0.45
    ) {
        let startedAtMs = startedAtMs ?? nowMs
        let elapsedMs = max(1_000, nowMs - startedAtMs)
        recordAttempt(
            success: false,
            repSnapshot: repSnapshot,
            elapsedMs: elapsedMs,
            estimatedKcal: estimatedKcal + kcalPerAttempt,
            detail: reason.missedAttemptDetail
        )
    }

    mutating func recordRejectedAttempt(
        detail: String,
        repSnapshot: Int,
        nowMs: Int64,
        kcalPerAttempt: Double = 0.45
    ) {
        let startedAtMs = startedAtMs ?? nowMs
        let elapsedMs = max(1_000, nowMs - startedAtMs)
        recordAttempt(
            success: false,
            repSnapshot: repSnapshot,
            elapsedMs: elapsedMs,
            estimatedKcal: estimatedKcal + kcalPerAttempt,
            detail: detail
        )
    }

    mutating func seedFromLiveCounterIfNeeded(reps liveReps: Int, durationMs: Int64) {
        guard !hasActivity, liveReps > 0 else { return }

        for rep in 1...liveReps {
            let elapsedMs = max(1_000, (durationMs * Int64(rep)) / Int64(max(1, liveReps)))
            recordAttempt(
                success: true,
                repSnapshot: rep,
                elapsedMs: elapsedMs,
                estimatedKcal: Double(rep) * 0.6,
                detail: "Live MediaPipe barbell press rep counted from camera tracking."
            )
        }
    }

    mutating func seedFromLiveCounterIfNeeded(
        reps liveReps: Int,
        durationMs: Int64,
        detail: String
    ) {
        guard !hasActivity, liveReps > 0 else { return }

        for rep in 1...liveReps {
            let elapsedMs = max(1_000, (durationMs * Int64(rep)) / Int64(max(1, liveReps)))
            recordAttempt(
                success: true,
                repSnapshot: rep,
                elapsedMs: elapsedMs,
                estimatedKcal: Double(rep) * 0.6,
                detail: detail
            )
        }
    }

    mutating func seedPlaceholderActivityIfNeeded(durationMs: Int64) {
        guard !hasActivity else { return }

        recordAttempt(
            success: true,
            repSnapshot: 1,
            elapsedMs: max(1_000, durationMs / 3),
            estimatedKcal: 0.6,
            detail: "Clean attempt recorded at session finish."
        )
        recordAttempt(
            success: false,
            repSnapshot: 1,
            elapsedMs: max(1_000, (durationMs * 2) / 3),
            estimatedKcal: 1.1,
            detail: "Missed attempt recorded at session finish."
        )
        recordAttempt(
            success: true,
            repSnapshot: 2,
            elapsedMs: durationMs,
            estimatedKcal: 1.7,
            detail: "Clean attempt recorded at session finish."
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
