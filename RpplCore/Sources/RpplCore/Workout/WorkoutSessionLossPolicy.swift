import Foundation

/// Decides whether an `HKWorkoutSession` state callback means the workout session died under us
/// while Rppl is recording (another app started a workout, `healthd` failed). Without a workout
/// session watchOS suspends the app once the wrist goes down and recording silently stops.
public enum WorkoutSessionLossPolicy {
    /// Raw values of `HKWorkoutSessionState`, mirrored so this stays free of HealthKit.
    public enum StateRaw {
        public static let ended = 3
        public static let stopped = 6
    }

    /// Detector id of the marker written to `detections.jsonl` when the session is lost.
    public static let detectorId = "hk_session_lost"

    /// - Parameters:
    ///   - isCurrentSession: the callback's session is the controller's current `workoutSession`.
    ///   - isStopping: Rppl itself is stopping or discarding (we asked for `.stopped`/`.ended`).
    public static func isUnexpectedLoss(
        isRunning: Bool,
        isStopping: Bool,
        isCurrentSession: Bool = true,
        toStateRaw: Int
    ) -> Bool {
        guard isRunning, !isStopping, isCurrentSession else { return false }
        return toStateRaw == StateRaw.ended || toStateRaw == StateRaw.stopped
    }

    /// An `HKWorkoutSession` failure is a loss under the same conditions, whatever the state.
    public static func isUnexpectedFailure(
        isRunning: Bool,
        isStopping: Bool,
        isCurrentSession: Bool = true
    ) -> Bool {
        isRunning && !isStopping && isCurrentSession
    }
}
