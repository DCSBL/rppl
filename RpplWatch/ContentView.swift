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
            session.refreshPermissionStatus()
            Task { await session.requestPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            WakeLog.debug(.lifecycle, "WKApplication.didBecomeActive")
            transfer.refreshSyncState()
        }
    }
}

#Preview {
    ContentView()
}
