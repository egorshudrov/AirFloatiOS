import Foundation

enum MediaPipePoseModelResource {
    static let name = "pose_landmarker_lite"
    static let fileExtension = "task"

    static var path: String? {
        Bundle.main.path(
            forResource: name,
            ofType: fileExtension
        )
    }

    static var isBundled: Bool {
        path != nil
    }

    static var diagnosticText: String {
        if let path {
            return "MediaPipe model bundled: \(URL(fileURLWithPath: path).lastPathComponent)"
        }

        return "MediaPipe model missing from app bundle."
    }
}
