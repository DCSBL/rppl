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
                WatchSessionController.shared.recoverOrphanedSessions()
                WatchTransferService.shared.refreshSyncState()
                WatchTransferService.shared.transferPending()
            }
        }
    }

    init() {
        WakeLog.debug(.lifecycle, "RpplWatchApp init")
        _ = TesterIdentity.resolve()
        WatchTransferService.shared.activate()
        Task.detached(priority: .utility) {
            await WatchSessionController.shared.recoverDanglingWorkoutSession()
        }
    }
}
