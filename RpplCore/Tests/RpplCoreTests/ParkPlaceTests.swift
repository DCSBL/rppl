import Foundation
import Testing
@testable import RpplCore

struct ParkPlaceTests {
    private func park(address: String?, timezone: String? = nil) -> Park {
        Park(id: "p", name: "P", location: ParkCoordinate(lat: 52, lon: 5), address: address, timezone: timezone)
    }

    @Test func cityFollowsThePostcode() {
        #expect(park(address: "Kosboulevard 35, 3059 XZ Rotterdam").cityName == "Rotterdam")
        #expect(park(address: "Duinenwater 41, 8300 Knokke-Heist").cityName == "Knokke-Heist")
        #expect(park(address: "Straat 1, 2321 Meer, Hoogstraten").cityName == "Meer, Hoogstraten")
    }

    @Test func cityFallsBackToLastPartOrNil() {
        #expect(park(address: "Somewhere 1, Utrecht").cityName == "Utrecht")
        #expect(park(address: nil).cityName == nil)
        #expect(park(address: "  ").cityName == nil)
    }

    @Test func subtitleAddsCountryFromTimeZone() {
        let english = Locale(identifier: "en")
        #expect(park(address: "A 1, 8300 Knokke-Heist", timezone: "Europe/Brussels").placeSubtitle(locale: english) == "Knokke-Heist, Belgium")
        #expect(park(address: "A 1, 3059 XZ Rotterdam").placeSubtitle(locale: Locale(identifier: "nl")) == "Rotterdam, Nederland")
    }

    @Test func subtitleSkipsUnknownCountryAndMissingCity() {
        #expect(park(address: "A 1, 1000 Town", timezone: "Asia/Tokyo").placeSubtitle(locale: Locale(identifier: "en")) == "Town")
        #expect(park(address: nil).placeSubtitle(locale: Locale(identifier: "en")) == "Netherlands")
    }
}
