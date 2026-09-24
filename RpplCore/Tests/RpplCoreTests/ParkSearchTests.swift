import Foundation
import Testing
@testable import RpplCore

struct ParkSearchTests {
    private let downUnder = Park(
        id: "downunder-nieuwegein",
        name: "Cable Park Down Under",
        location: ParkCoordinate(lat: 52.0, lon: 5.0),
        address: "Ravensewetering 1, 3439 ZZ Nieuwegein"
    )
    private let project7 = Park(
        id: "project7-rotterdam",
        name: "Project 7 Cablepark Rotterdam",
        location: ParkCoordinate(lat: 51.9, lon: 4.5),
        address: "Nieuw Mathenesserstraat 100, Rotterdam"
    )

    private var parks: [Park] { [downUnder, project7] }

    @Test func emptyQueryReturnsAllParksUnchanged() {
        #expect(ParkSearch.filter(parks, query: "").map(\.id) == parks.map(\.id))
        #expect(ParkSearch.filter(parks, query: "   ").map(\.id) == parks.map(\.id))
    }

    @Test func matchesByNameAlone() {
        #expect(ParkSearch.filter(parks, query: "project").map(\.id) == ["project7-rotterdam"])
    }

    @Test func matchesByAddressAlone() {
        #expect(ParkSearch.filter(parks, query: "rotterdam").map(\.id) == ["project7-rotterdam"])
    }

    @Test func matchesAcrossNameAndAddressRegardlessOfWordOrder() {
        // "nieuwegein down" should find "Down Under" · address "... Nieuwegein".
        #expect(ParkSearch.filter(parks, query: "nieuwegein down").map(\.id) == ["downunder-nieuwegein"])
        #expect(ParkSearch.filter(parks, query: "down under nieuwegein").map(\.id) == ["downunder-nieuwegein"])
    }

    @Test func isTypoTolerant() {
        #expect(ParkSearch.filter(parks, query: "nieuwegien").map(\.id) == ["downunder-nieuwegein"])
        #expect(ParkSearch.filter(parks, query: "rotterdm").map(\.id) == ["project7-rotterdam"])
    }

    @Test func isDiacriticAndCaseInsensitive() {
        #expect(ParkSearch.filter(parks, query: "PROJECT").map(\.id) == ["project7-rotterdam"])
    }

    @Test func requiresEveryQueryWordToMatch() {
        #expect(ParkSearch.filter(parks, query: "project amsterdam").isEmpty)
    }

    @Test func noMatchReturnsEmpty() {
        #expect(ParkSearch.filter(parks, query: "xyzxyz").isEmpty)
    }
}
