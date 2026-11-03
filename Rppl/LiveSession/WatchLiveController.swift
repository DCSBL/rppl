import HealthKit
import Observation
import RpplCore

/// Receives the Watch's mirrored workout and its live numbers (`WatchLiveSnapshot`). A viewing window
/// only: the session itself still arrives through the normal transfer when it ends.
@Observable
@MainActor
final class WatchLiveController: NSObject {
    static let shared = WatchLiveController()

    private(set) var snapshot: WatchLiveSnapshot?
    private var mirrored: HKWorkoutSession?
    private var lastActivityUpdate = Date.distantPast
    /// ActivityKit budgets updates: no more often than this.
    private static let activityInterval: TimeInterval = 10

    /// Call once at launch: the handler must exist before the Watch starts mirroring.
    func register() {
        HKHealthStore().workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
    }

    private func adopt(_ session: HKWorkoutSession) {
        WakeLog.debug(.sync, "watch workout mirrored")
        mirrored = session
        session.delegate = self
    }

    private func receive(_ data: Data) {
        guard let new = WatchLiveSnapshot.decode(data) else { return }
        snapshot = new
        if Date.now.timeIntervalSince(lastActivityUpdate) >= Self.activityInterval {
            lastActivityUpdate = .now
            LiveSessionActivityManager.sync(new)
        }
    }

    private func finish() {
        mirrored = nil
        snapshot = nil
        lastActivityUpdate = .distantPast
        LiveSessionActivityManager.end()
    }
}

extension WatchLiveController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in finish() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in finish() }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        guard let last = data.last else { return }
        Task { @MainActor in receive(last) }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor in finish() }
    }
}
