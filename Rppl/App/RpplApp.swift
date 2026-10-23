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
            if phase == .background, !UITestFixtures.isActive {
                Task { @MainActor in await ParkDataBackgroundRefresh.updateSchedule() }
            }
            if phase == .active, !UITestFixtures.isActive {
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
        ParkDataBackgroundRefresh.register()
        if UITestFixtures.isActive {
            UITestFixtures.seed()
        } else {
            PhoneICloudDriveController.shared.start()
        }
    }
}
