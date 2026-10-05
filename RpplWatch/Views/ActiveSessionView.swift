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
        TabView(selection: $tab) {
            SessionControlsPage(session: session)
                .tag(SessionTab.controls)
            SessionSetUIPage(session: session)
                .tag(SessionTab.activity)
            if AppReleaseChannel.allowsDebugTools {
                WatchDebugPage(session: session)
                    .tag(SessionTab.debug)
            }
        }
        .overlay(alignment: .top) {
            // Includes `hk_missing`: no workout session = no background runtime.
            RecordingIssueBadge(issues: session.recordingIssues)
        }
    }
}
