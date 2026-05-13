import Foundation

enum LiveDiagnosticsPolicy {
    #if DEBUG
    static let showsSquatDebugEventStrip = true
    #else
    static let showsSquatDebugEventStrip = false
    #endif
}
