import SwiftUI

struct ActiveSessionView: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        TabView {
            SessionControlsPage(session: session)
            SessionMetricsPage(session: session)
        }
        .tabViewStyle(.verticalPage)
    }
}
