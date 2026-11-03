import HealthKit
import RpplCore
import SwiftUI
import WatchKit

/// The iPhone's "Start on Apple Watch" (`HKHealthStore.startWatchApp`) launches this app and lands here.
/// It takes the same path as the Action Button: a busy or blocked Watch ignores it.
final class RpplWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WakeLog.debug(.intent, "start request from iPhone")
        Task { await WatchSessionController.shared.handleStartWorkoutIntent() }
    }
}
