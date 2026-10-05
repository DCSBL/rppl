import SwiftUI
import WatchKit
import RpplCore

struct ContentView: View {
    @State private var session = WatchSessionController.shared
    @State private var transfer = WatchTransferService.shared

    private var debugOverrideSize: CGSize? {
        guard AppReleaseChannel.allowsDebugTools else { return nil }
        return session.debugScreenSize.size
    }

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
            } else {
                // No permission screen at launch: system sheets only appear when a session starts
                // (`startSession`). Browsable even when a permission is denied: logbook and
                // sessions stay viewable, Start explains what to allow.
                IdleSessionView(session: session, transfer: transfer)
            }
        }
        .modifier(DebugScreenSizeOverride(size: debugOverrideSize))
        .onAppear {
            WakeLog.debug(.lifecycle, "Watch ContentView onAppear")
            // WatchTransferService.shared already activated at app launch (RpplWatchApp.init());
            // re-activating on every appear was redundant and re-triggered WC's own console spam.
            transfer.refreshSyncState()
            // Reads status only; never presents a system sheet.
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
