import HealthKit
import RpplCore

/// Asks the paired Apple Watch to open Rppl and start a session, like the Action Button does.
/// No authorization sheet: it only launches the Watch app, which asks for its own permissions.
enum WatchStarter {
    static func start() async -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = .waterSports
        config.locationType = .outdoor
        let store = HKHealthStore()
        return await withCheckedContinuation { continuation in
            store.startWatchApp(with: config) { success, error in
                if let error { WakeLog.debug(.sync, "start Apple Watch: \(error.localizedDescription)") }
                continuation.resume(returning: success)
            }
        }
    }
}
