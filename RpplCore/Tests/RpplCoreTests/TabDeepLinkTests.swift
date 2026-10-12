import Foundation
import Testing
@testable import RpplCore

struct TabDeepLinkTests {
    @Test func everyTabRoundTrips() throws {
        for tab in TabDeepLink.allCases {
            let url = try #require(tab.url)
            #expect(url.absoluteString == "rppl://\(tab.rawValue)")
            #expect(TabDeepLink(url: url) == tab)
        }
    }

    @Test func ignoresOtherLinks() throws {
        #expect(TabDeepLink(url: try #require(URL(string: "https://logbook"))) == nil)
        #expect(TabDeepLink(url: try #require(URL(string: "rppl://unknown"))) == nil)
        #expect(TabDeepLink(url: try #require(ParkDeepLink.favoritesURL)) == nil)
        #expect(TabDeepLink(url: try #require(ParkDeepLink.url(forParkID: "x"))) == nil)
        #expect(TabDeepLink(url: try #require(SessionDeepLink.url(forSessionID: "x"))) == nil)
    }

    @Test func catalogExamplesAreHandled() throws {
        for entry in DeepLinkCatalog.entries {
            let url = try #require(URL(string: entry.url.replacingOccurrences(of: "<session-id>", with: "s1").replacingOccurrences(of: "<park-id>", with: "p1")))
            let handled = TabDeepLink(url: url) != nil || ParkDeepLink.isFavorites(url)
                || ParkDeepLink.parkID(from: url) != nil || SessionDeepLink.sessionID(from: url) != nil
            #expect(handled, "\(entry.url)")
        }
    }
}
