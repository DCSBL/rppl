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
            } else if session.areRecordingPermissionsReady {
                IdleSessionView(session: session, transfer: transfer)
            } else {
                PermissionsOnboardingView(session: session)
            }
        }
        .onAppear {
            WakeLog.debug(.lifecycle, "Watch ContentView onAppear")
            transfer.activate()
            transfer.refreshSyncState()
            // Do not present permission sheets here — PermissionsOnboardingView owns asks.
            session.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            WakeLog.debug(.lifecycle, "WKApplication.didBecomeActive")
            transfer.refreshSyncState()
            session.refreshPermissionStatus()
        }
    }
}

#Preview {
    ContentView()
}
