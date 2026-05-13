import Foundation
@preconcurrency import Vision

struct LivePoseDiagnosticLandmark: Equatable {
    let label: String
    let confidence: Float?

    var isVisible: Bool {
        guard let confidence else { return false }
        return confidence >= 0.15
    }

    var confidenceText: String {
        guard let confidence else { return "--" }
        return "\(Int((confidence * 100).rounded()))%"
    }
}

struct LivePoseDiagnostics: Equatable {
    let leftShoulder: LivePoseDiagnosticLandmark
    let leftElbow: LivePoseDiagnosticLandmark
    let leftWrist: LivePoseDiagnosticLandmark
    let leftHip: LivePoseDiagnosticLandmark
    let leftKnee: LivePoseDiagnosticLandmark
    let rightShoulder: LivePoseDiagnosticLandmark
    let rightElbow: LivePoseDiagnosticLandmark
    let rightWrist: LivePoseDiagnosticLandmark
    let rightHip: LivePoseDiagnosticLandmark
    let rightKnee: LivePoseDiagnosticLandmark
    let confidentLandmarkCount: Int

    static let empty = LivePoseDiagnostics(
        leftShoulder: LivePoseDiagnosticLandmark(label: "L shoulder", confidence: nil),
        leftElbow: LivePoseDiagnosticLandmark(label: "L elbow", confidence: nil),
        leftWrist: LivePoseDiagnosticLandmark(label: "L wrist", confidence: nil),
        leftHip: LivePoseDiagnosticLandmark(label: "L hip", confidence: nil),
        leftKnee: LivePoseDiagnosticLandmark(label: "L knee", confidence: nil),
        rightShoulder: LivePoseDiagnosticLandmark(label: "R shoulder", confidence: nil),
        rightElbow: LivePoseDiagnosticLandmark(label: "R elbow", confidence: nil),
        rightWrist: LivePoseDiagnosticLandmark(label: "R wrist", confidence: nil),
        rightHip: LivePoseDiagnosticLandmark(label: "R hip", confidence: nil),
        rightKnee: LivePoseDiagnosticLandmark(label: "R knee", confidence: nil),
        confidentLandmarkCount: 0
    )

    var leftArmComplete: Bool {
        leftShoulder.isVisible && leftElbow.isVisible && leftWrist.isVisible
    }

    var rightArmComplete: Bool {
        rightShoulder.isVisible && rightElbow.isVisible && rightWrist.isVisible
    }

    var summary: String {
        let left = leftArmComplete ? "LEFT ARM OK" : "LEFT ARM MISSING"
        let right = rightArmComplete ? "RIGHT ARM OK" : "RIGHT ARM MISSING"
        return "\(left) · \(right) · \(confidentLandmarkCount) confident points"
    }

    static func build(from frame: LivePoseFrame) -> LivePoseDiagnostics {
        LivePoseDiagnostics(
            leftShoulder: diagnostic("L shoulder", .leftShoulder, frame),
            leftElbow: diagnostic("L elbow", .leftElbow, frame),
            leftWrist: diagnostic("L wrist", .leftWrist, frame),
            leftHip: diagnostic("L hip", .leftHip, frame),
            leftKnee: diagnostic("L knee", .leftKnee, frame),
            rightShoulder: diagnostic("R shoulder", .rightShoulder, frame),
            rightElbow: diagnostic("R elbow", .rightElbow, frame),
            rightWrist: diagnostic("R wrist", .rightWrist, frame),
            rightHip: diagnostic("R hip", .rightHip, frame),
            rightKnee: diagnostic("R knee", .rightKnee, frame),
            confidentLandmarkCount: frame.confidentLandmarkCount()
        )
    }

    private static func diagnostic(
        _ label: String,
        _ jointName: VNHumanBodyPoseObservation.JointName,
        _ frame: LivePoseFrame
    ) -> LivePoseDiagnosticLandmark {
        LivePoseDiagnosticLandmark(
            label: label,
            confidence: frame.landmark(jointName, minConfidence: 0)?.confidence
        )
    }
}
