import SwiftUI
import WakeTrackerCore

@main
struct WakeTrackerWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            WakeLog.debug(.lifecycle, "scenePhase → \(String(describing: phase))")
        }
    }

    init() {
        WakeLog.debug(.lifecycle, "WakeTrackerWatchApp init")
        WatchTransferService.shared.activate()
    }
}
