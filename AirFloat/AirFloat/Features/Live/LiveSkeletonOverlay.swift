import SwiftUI
@preconcurrency import Vision

struct LiveSkeletonOverlay: View {
    let frame: LivePoseFrame?

    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(connections.enumerated()), id: \.offset) { _, connection in
                    if let start = point(for: connection.0, in: proxy.size),
                       let end = point(for: connection.1, in: proxy.size)
                    {
                        Path { path in
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                        .stroke(Color.green.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                }

                ForEach(visiblePoints(in: proxy.size), id: \.name) { point in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.green, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .position(point.point)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func visiblePoints(in size: CGSize) -> [(name: String, point: CGPoint)] {
        guard let frame else { return [] }
        return frame.landmarks
            .filter { $0.confidence >= 0.15 && $0.x.isFinite && $0.y.isFinite }
            .map { landmark in
                (
                    name: landmark.name,
                    point: displayPoint(for: landmark, in: size)
                )
            }
    }

    private func point(
        for jointName: VNHumanBodyPoseObservation.JointName,
        in size: CGSize
    ) -> CGPoint? {
        guard let landmark = frame?.landmark(jointName, minConfidence: 0.15) else {
            return nil
        }

        return displayPoint(for: landmark, in: size)
    }

    private func displayPoint(for landmark: LivePoseLandmark, in size: CGSize) -> CGPoint {
        let normalizedPoint = rotatedPortraitPoint(for: landmark)
        let sourceSize = CGSize(width: 3, height: 4)
        let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
        let drawnSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (size.width - drawnSize.width) * 0.5,
            y: (size.height - drawnSize.height) * 0.5
        )

        return CGPoint(
            x: origin.x + normalizedPoint.x * drawnSize.width,
            y: origin.y + normalizedPoint.y * drawnSize.height
        )
    }

    private func rotatedPortraitPoint(for landmark: LivePoseLandmark) -> CGPoint {
        let rawX = landmark.x.clamped(to: 0...1)
        let rawY = landmark.y.clamped(to: 0...1)

        return CGPoint(
            x: rawY,
            y: 1 - rawX
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
