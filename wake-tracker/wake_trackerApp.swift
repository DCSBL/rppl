import SwiftUI
import WakeTrackerCore

@main
struct wake_trackerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            WakeLog.debug(.lifecycle, "scenePhase → \(String(describing: phase))")
            if phase == .active {
                PhoneConnectivityService.shared.refreshSyncState()
                PhoneConnectivityService.shared.flushPendingAcks()
            }
        }
    }

    init() {
        WakeLog.debug(.lifecycle, "wake_trackerApp init")
        PhoneConnectivityService.shared.activate()
    }
}
