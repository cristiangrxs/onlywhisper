import Foundation

enum ModelLoadGuard {
    /// A load that finishes after `unload()` must be dropped so the next dictation opens the new files.
    static func keeps(started: Int, current: Int) -> Bool {
        started == current
    }
}
