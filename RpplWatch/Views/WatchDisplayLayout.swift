import WatchKit

/// Watch screen layout helpers for optional UI chrome.
enum WatchDisplayLayout {
    /// Ultra-class screens (~49 mm) have room for a trailing session-overview map pin.
    static var showsSessionOverviewStartMap: Bool {
        WKInterfaceDevice.current().screenBounds.width >= 204
    }
}
