@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPipeTasksVision
import UIKit

struct MediaPipeLivePoseSourceFrame {
    let frame: LivePoseFrame
    let timestampMs: Int
    let latencyMs: Double
}

struct MediaPipeLivePoseConfiguration: Equatable {
    let minPoseDetectionConfidence: Float
    let minPosePresenceConfidence: Float
    let minTrackingConfidence: Float

    static func configuration(for exerciseKey: ExerciseKey) -> MediaPipeLivePoseConfiguration {
        switch exerciseKey {
        case .pushup, .situp:
            return MediaPipeLivePoseConfiguration(
                minPoseDetectionConfidence: 0.35,
                minPosePresenceConfidence: 0.35,
                minTrackingConfidence: 0.30
            )
        case .pressBarbell, .pressDumbbell, .squatBeta:
            return MediaPipeLivePoseConfiguration(
                minPoseDetectionConfidence: 0.50,
                minPosePresenceConfidence: 0.50,
                minTrackingConfidence: 0.50
            )
        }
    }
}

final class MediaPipeLivePoseSource: NSObject {
    var onFrame: ((MediaPipeLivePoseSourceFrame) -> Void)?
    var onError: ((String) -> Void)?

    private var landmarker: PoseLandmarker?
    private var lastTimestampMs = 0
    private var submittedAtByTimestamp: [Int: TimeInterval] = [:]

    init(modelPath: String, configuration: MediaPipeLivePoseConfiguration) throws {
        super.init()

        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelPath
        baseOptions.delegate = .CPU

        let options = PoseLandmarkerOptions()
        options.baseOptions = baseOptions
        options.runningMode = .liveStream
        options.poseLandmarkerLiveStreamDelegate = self
        options.numPoses = 1
        options.minPoseDetectionConfidence = configuration.minPoseDetectionConfidence
        options.minPosePresenceConfidence = configuration.minPosePresenceConfidence
        options.minTrackingConfidence = configuration.minTrackingConfidence

        do {
            landmarker = try PoseLandmarker(options: options)
        } catch {
            throw MediaPipeLivePoseSourceError.initializationFailed(error.localizedDescription)
        }
    }

    func process(sampleBuffer: CMSampleBuffer, timestampMs: Int) {
        let nextTimestampMs = max(timestampMs, lastTimestampMs + 1)
        lastTimestampMs = nextTimestampMs

        do {
            let image = try MPImage(sampleBuffer: sampleBuffer, orientation: .leftMirrored)
            submittedAtByTimestamp[nextTimestampMs] = ProcessInfo.processInfo.systemUptime
            try landmarker?.detectAsync(image: image, timestampInMilliseconds: nextTimestampMs)
        } catch {
            onError?("MediaPipe pose frame failed: \(error.localizedDescription)")
        }
    }
}

enum MediaPipeLivePoseSourceError: Error, Equatable {
    case initializationFailed(String)
}

extension MediaPipeLivePoseSource: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            onError?("MediaPipe pose callback failed: \(error.localizedDescription)")
            return
        }

        guard let landmarks = result?.landmarks.first else {
            onFrame?(
                MediaPipeLivePoseSourceFrame(
                    frame: LivePoseFrame(landmarks: []),
                    timestampMs: timestampInMilliseconds,
                    latencyMs: latencyMs(for: timestampInMilliseconds)
                )
            )
            return
        }

        let indexedLandmarks = landmarks.enumerated().map { index, landmark in
            (
                index: index,
                x: landmark.x,
                y: landmark.y,
                confidence: landmark.visibility?.floatValue ?? landmark.presence?.floatValue ?? 1
            )
        }

        onFrame?(
            MediaPipeLivePoseSourceFrame(
                frame: .buildFromMediaPipeIndexedLandmarks(indexedLandmarks),
                timestampMs: timestampInMilliseconds,
                latencyMs: latencyMs(for: timestampInMilliseconds)
            )
        )
    }

    private func latencyMs(for timestampMs: Int) -> Double {
        guard let submittedAt = submittedAtByTimestamp.removeValue(forKey: timestampMs) else {
            return 0
        }

        return max(0, (ProcessInfo.processInfo.systemUptime - submittedAt) * 1_000)
    }
}
