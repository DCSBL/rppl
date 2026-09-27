import SwiftUI
import WatchKit
import RpplCore

struct ContentView: View {
    @State private var session = WatchSessionController.shared
    @State private var transfer = WatchTransferService.shared

    var body: some View {
        Group {
            if let summary = session.endedSessionSummary {
                SessionEndSummaryView(
                    summary: summary,
                    session: session,
                    transfer: transfer
                )
            } else if session.isRunning {
                ActiveSessionView(session: session)
            } else if !session.isHealthPermissionResolved {
                // Health status loads off-main; avoid flashing onboarding for returning users.
                ProgressView()
            } else if session.areRecordingPermissionsReady {
                IdleSessionView(session: session, transfer: transfer)
            } else {
                PermissionsOnboardingView(session: session)
            }
        }
        .onAppear {
            WakeLog.debug(.lifecycle, "Watch ContentView onAppear")
            // WatchTransferService.shared already activated at app launch (RpplWatchApp.init());
            // re-activating on every appear was redundant and re-triggered WC's own console spam.
            transfer.refreshSyncState()
            // PermissionsOnboardingView auto-presents system sheets on first boot.
            session.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            WakeLog.debug(.lifecycle, "WKApplication.didBecomeActive")
            transfer.refreshSyncState()
            session.refreshPermissionStatus()
            transfer.transferPending()
            WatchViewSyncService.shared.requestViewSyncIfReachable()
        }
    }
}

#Preview {
    ContentView()
}
