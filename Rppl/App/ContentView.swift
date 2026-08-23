import SwiftUI

private enum AppTab: Hashable {
    case logbook
    case app
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .logbook

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Logbook", systemImage: "book.closed.fill", value: AppTab.logbook) {
                LogbookView()
            }

            Tab("rppl", systemImage: "app.fill", value: AppTab.app) {
                AppInfoView()
            }
        }
        .tint(Color.rpplAccent)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    ContentView()
}
