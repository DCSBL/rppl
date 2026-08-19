import SwiftUI

private enum SessionTab: Hashable {
    case controls
    case activity
}

struct ActiveSessionView: View {
    @Bindable var session: WatchSessionController
    @State private var tab: SessionTab = .activity

    var body: some View {
        TabView(selection: $tab) {
            SessionControlsPage(session: session)
                .tag(SessionTab.controls)
            SessionRideUIPage(session: session)
                .tag(SessionTab.activity)
        }
    }
}
