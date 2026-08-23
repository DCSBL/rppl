import SwiftUI
import WatchKit
import RpplCore

struct ContentView: View {
    @State private var session = WatchSessionController.shared
    @State private var transfer = WatchTransferService.shared

    var body: some View {
        Group {
            if session.isRunning {
                ActiveSessionView(session: session)
            } else {
                IdleSessionView(session: session, transfer: transfer)
            }
        }
        .onAppear {
            WakeLog.debug(.lifecycle, "Watch ContentView onAppear")
            transfer.activate()
            transfer.refreshSyncState()
            // Refresh labels only — do not present Health/location sheets at cold launch.
            // Sheets fire from startSession and Idle Sync "Permissions".
            session.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            WakeLog.debug(.lifecycle, "WKApplication.didBecomeActive")
            transfer.refreshSyncState()
            transfer.transferPending()
        }
    }
}

#Preview {
    ContentView()
}
