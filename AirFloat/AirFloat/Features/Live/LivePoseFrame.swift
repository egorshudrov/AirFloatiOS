import Foundation
@preconcurrency import Vision

enum LivePoseLandmarkName {
    static let leftShoulder = VNHumanBodyPoseObservation.JointName.leftShoulder.rawValue.rawValue
    static let leftElbow = VNHumanBodyPoseObservation.JointName.leftElbow.rawValue.rawValue
    static let leftWrist = VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue
    static let rightShoulder = VNHumanBodyPoseObservation.JointName.rightShoulder.rawValue.rawValue
    static let rightElbow = VNHumanBodyPoseObservation.JointName.rightElbow.rawValue.rawValue
    static let rightWrist = VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue
    static let leftHip = VNHumanBodyPoseObservation.JointName.leftHip.rawValue.rawValue
    static let rightHip = VNHumanBodyPoseObservation.JointName.rightHip.rawValue.rawValue
    static let leftKnee = VNHumanBodyPoseObservation.JointName.leftKnee.rawValue.rawValue
    static let rightKnee = VNHumanBodyPoseObservation.JointName.rightKnee.rawValue.rawValue
    static let leftAnkle = VNHumanBodyPoseObservation.JointName.leftAnkle.rawValue.rawValue
    static let rightAnkle = VNHumanBodyPoseObservation.JointName.rightAnkle.rawValue.rawValue
}

struct LivePoseLandmark: Equatable, Sendable {
    let name: String
    let x: Double
    let y: Double
    let confidence: Float
}

struct LivePoseFrame: Equatable, Sendable {
    let landmarks: [LivePoseLandmark]

    var landmarkCount: Int {
        landmarks.count
    }

    func confidentLandmarkCount(minConfidence: Float = 0.3) -> Int {
        landmarks.filter { $0.confidence >= minConfidence }.count
    }

    func landmark(
        _ jointName: VNHumanBodyPoseObservation.JointName,
        minConfidence: Float = 0.3
    ) -> LivePoseLandmark? {
        let name = jointName.rawValue.rawValue
        return landmarks.first { $0.name == name && $0.confidence >= minConfidence }
    }

    static func build(
        from observation: VNHumanBodyPoseObservation,
        minConfidence: Float = 0.0
    ) throws -> LivePoseFrame {
        let recognizedPoints = try observation.recognizedPoints(.all)
        let landmarks = recognizedPoints.compactMap { key, point -> LivePoseLandmark? in
            guard point.confidence >= minConfidence else { return nil }

            return LivePoseLandmark(
                name: key.rawValue.rawValue,
                x: point.location.x,
                y: point.location.y,
                confidence: point.confidence
            )
        }
        .sorted { $0.name < $1.name }

        return LivePoseFrame(landmarks: landmarks)
    }
}

extension LivePoseFrame {
    static func buildFromMediaPipeIndexedLandmarks(_ indexedLandmarks: [(index: Int, x: Float, y: Float, confidence: Float)]) -> LivePoseFrame {
        let landmarks = indexedLandmarks.map { landmark in
            LivePoseLandmark(
                name: mediaPipeName(for: landmark.index),
                x: Double(landmark.x),
                y: Double(landmark.y),
                confidence: landmark.confidence
            )
        }

        return LivePoseFrame(landmarks: landmarks)
    }

    private static func mediaPipeName(for index: Int) -> String {
        switch index {
        case 11:
            return LivePoseLandmarkName.leftShoulder
        case 12:
            return LivePoseLandmarkName.rightShoulder
        case 13:
            return LivePoseLandmarkName.leftElbow
        case 14:
            return LivePoseLandmarkName.rightElbow
        case 15:
            return LivePoseLandmarkName.leftWrist
        case 16:
            return LivePoseLandmarkName.rightWrist
        case 23:
            return LivePoseLandmarkName.leftHip
        case 24:
            return LivePoseLandmarkName.rightHip
        case 25:
            return LivePoseLandmarkName.leftKnee
        case 26:
            return LivePoseLandmarkName.rightKnee
        case 27:
            return LivePoseLandmarkName.leftAnkle
        case 28:
            return LivePoseLandmarkName.rightAnkle
        default:
            return "mediapipe_\(index)"
        }
    }
}
