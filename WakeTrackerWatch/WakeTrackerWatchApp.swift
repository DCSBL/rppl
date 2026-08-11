import SwiftUI

@main
struct WakeTrackerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    init() {
        WatchTransferService.shared.activate()
    }
}
