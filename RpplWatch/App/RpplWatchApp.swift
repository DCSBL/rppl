import SwiftUI
import RpplCore

@main
struct RpplWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            WakeLog.debug(.lifecycle, "scenePhase → \(String(describing: phase))")
            if phase == .active {
                if !WatchSessionController.shared.isRecordingActive {
                    WatchSessionController.shared.recoverOrphanedSessions()
                }
                WatchTransferService.shared.refreshSyncState()
                WatchTransferService.shared.transferPending()
            }
        }
    }

    init() {
        WakeLog.debug(.lifecycle, "RpplWatchApp init")
        _ = TesterIdentity.resolve()
        // .shared's own init() already calls activate(); don't double-activate WCSession here.
        _ = WatchTransferService.shared
        // Stored on the controller so a Start in this same launch can wait for it.
        WatchSessionController.shared.startLaunchRecovery()
    }
}
