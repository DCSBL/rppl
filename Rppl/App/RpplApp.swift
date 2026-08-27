import SwiftUI
import RpplCore

@main
struct RpplApp: App {
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
        WakeLog.debug(.lifecycle, "RpplApp init")
        _ = TesterIdentity.resolve()
        PhoneConnectivityService.shared.activate()
    }
}
