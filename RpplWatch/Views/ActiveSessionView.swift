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
            // No workout session = no background runtime: recording only while the screen is on.
            if session.recordingMode == "sensorsOnly" {
                Text("Screen-on only")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.black)
                    .allowsHitTesting(false)
            }
        }
    }
}
