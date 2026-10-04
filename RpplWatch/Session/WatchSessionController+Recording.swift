import Foundation

extension WatchSessionController {
    /// A session is recording right now (not stopping). Heavy file work that is not part of the
    /// recording itself (scanning every stored session, view sync, recovery) waits until Stop, so a
    /// wrist raise can never stall the main thread of a running workout.
    var isRecordingActive: Bool {
        isRunning && !isStopping
    }
}
