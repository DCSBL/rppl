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
                Task { @MainActor in
                    await PhoneICloudDriveController.shared.refreshAvailability()
                    PhoneICloudDriveController.shared.applyPreferredRootIfNeeded(reason: "active")
                }
            }
        }
    }

    init() {
        WakeLog.enablePersistence(at: WakeLog.defaultHistoryURL)
        WakeLog.debug(.lifecycle, "RpplApp init")
        _ = TesterIdentity.resolve()
        // .shared's own init() already calls activate(); don't double-activate WCSession here.
        _ = PhoneConnectivityService.shared
        PhoneICloudDriveController.shared.start()
    }
}
