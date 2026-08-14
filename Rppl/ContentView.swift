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

            Tab("This app", systemImage: "app.fill", value: AppTab.app) {
                AppInfoView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background {
            TabBarLeadingAligner()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    ContentView()
}
