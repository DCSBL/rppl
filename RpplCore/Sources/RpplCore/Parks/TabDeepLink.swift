import Foundation

/// `rppl://logbook`, `rppl://parks`, `rppl://about`, `rppl://debug`: open a tab (debug is the hidden screen under About).
public enum TabDeepLink: String, CaseIterable {
    case logbook, parks, about, debug

    public var url: URL? {
        var components = URLComponents()
        components.scheme = ParkDeepLink.scheme
        components.host = rawValue
        return components.url
    }

    /// Only the bare host matches, so `rppl://parks/favorites` stays a `ParkDeepLink`.
    public init?(url: URL) {
        guard url.scheme == ParkDeepLink.scheme, url.path.isEmpty || url.path == "/",
              let link = TabDeepLink(rawValue: url.host ?? "") else { return nil }
        self = link
    }
}

/// Every link the app handles, for the Debug screen and `Docs/DeepLinks.md`.
public enum DeepLinkCatalog {
    public struct Entry: Equatable, Sendable {
        public let url: String
        public let summary: String
    }

    public static let entries: [Entry] = [
        Entry(url: "rppl://logbook", summary: "Logbook tab"),
        Entry(url: "rppl://session/<session-id>", summary: "Session detail in the logbook"),
        Entry(url: "rppl://parks", summary: "Parks tab"),
        Entry(url: "rppl://parks/favorites", summary: "Parks tab, starred parks only"),
        Entry(url: "rppl://park/<park-id>", summary: "Park detail"),
        Entry(url: "rppl://about", summary: "Settings, opens the Rppl modal"),
        Entry(url: "rppl://debug", summary: "Hidden Debug screen"),
    ]
}
