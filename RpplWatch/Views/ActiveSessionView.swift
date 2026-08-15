import SwiftUI

struct ActiveSessionView: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        TabView {
            SessionControlsPage(session: session)
            SessionRideUIPage(session: session)
            SessionDebugPage(session: session)
        }
    }
}
