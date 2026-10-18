import SwiftUI
import RpplCore

private enum SessionTab: Hashable {
    case controls
    case activity
    case debug
}

struct ActiveSessionView: View {
    @Bindable var session: WatchSessionController
    @State private var tab: SessionTab = .activity

    var body: some View {
        // Controls (Stop/Pause/Water) stay unreachable while Water Lock is on: Water Lock exists to stop
        // accidental taps, so the page must not be reachable by a stray swipe or Crown turn.
        TabView(selection: lockedTab) {
            SessionControlsPage(session: session)
                .tag(SessionTab.controls)
            SessionSetUIPage(session: session)
                .tag(SessionTab.activity)
            if WatchDebugTools.isEnabled {
                WatchDebugPage(session: session)
                    .tag(SessionTab.debug)
            }
        }
        .onChange(of: session.isWaterLockEnabled) { _, locked in
            guard locked else { return }
            withAnimation { tab = .activity }
        }
        // Polled here (not on the controls page) so a lock enabled at session start is seen while
        // the controls page is off screen.
        .task {
            while !Task.isCancelled {
                session.refreshWaterLockState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .overlay(alignment: .top) {
            // Includes `hk_missing`: no workout session = no background runtime.
            RecordingIssueBadge(issues: session.recordingIssues)
        }
    }

    private var lockedTab: Binding<SessionTab> {
        Binding(
            get: { session.isWaterLockEnabled && tab == .controls ? .activity : tab },
            set: { newTab in
                guard !(session.isWaterLockEnabled && newTab == .controls) else { return }
                tab = newTab
            }
        )
    }
}
