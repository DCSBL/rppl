import Foundation
import Testing
@testable import RpplCore

struct ParkSpotlightTests {
    private let english = Locale(identifier: "en")

    private func park(
        id: String = "project-7",
        name: String = "Project 7 Cablepark Rotterdam",
        shortName: String? = nil,
        address: String? = "Kosboulevard 35, 3059 XZ Rotterdam",
        closed: Bool? = nil
    ) -> Park {
        Park(
            id: id,
            name: name,
            shortName: shortName,
            location: ParkCoordinate(lat: 51.95, lon: 4.52),
            address: address,
            permanentlyClosed: closed
        )
    }

    @Test func entryDescribesThePark() throws {
        let entry = try #require(ParkSpotlight.entries(for: [park(shortName: "Project 7")], locale: english).first)
        #expect(entry.identifier == "rppl://park/project-7")
        #expect(entry.title == "Project 7 Cablepark Rotterdam")
        #expect(entry.subtitle == "Rotterdam, Netherlands")
        #expect(entry.latitude == 51.95)
        #expect(entry.longitude == 4.52)
        #expect(entry.keywords == ["Project 7"] + ParkSpotlight.genericKeywords)
    }

    @Test func subtitleFollowsTheLocale() throws {
        let entry = try #require(ParkSpotlight.entries(for: [park()], locale: Locale(identifier: "nl")).first)
        #expect(entry.subtitle == "Rotterdam, Nederland")
    }

    @Test func subtitleIsMissingWithoutAddressAndCountry() throws {
        let zone = Park(id: "x", name: "X", location: ParkCoordinate(lat: 1, lon: 2), timezone: "Asia/Tokyo")
        let entry = try #require(ParkSpotlight.entries(for: [zone], locale: english).first)
        #expect(entry.subtitle == nil)
    }

    @Test func shortNameOnlyCountsWhenItAddsAWord() throws {
        for shortName in [nil, "", "  ", "Project 7 Cablepark Rotterdam", "project 7 cablepark rotterdam"] {
            let entry = try #require(ParkSpotlight.entries(for: [park(shortName: shortName)], locale: english).first)
            #expect(entry.keywords == ParkSpotlight.genericKeywords, "short name \(String(describing: shortName))")
        }
    }

    @Test func closedParksAreLeftOut() {
        let entries = ParkSpotlight.entries(
            for: [park(id: "gone", closed: true), park(id: "open", closed: false), park(id: "unset")],
            locale: english
        )
        #expect(entries.map(\.identifier) == ["rppl://park/open", "rppl://park/unset"])
    }

    @Test func parksWithoutIdentityAreSkipped() {
        let entries = ParkSpotlight.entries(
            for: [park(id: ""), park(id: "blank-name", name: "  "), park(id: "fine")],
            locale: english
        )
        #expect(entries.map(\.identifier) == ["rppl://park/fine"])
    }

    @Test func entriesDoNotDependOnTheInputOrder() {
        let a = park(id: "a", name: "A")
        let b = park(id: "b", name: "B")
        #expect(ParkSpotlight.entries(for: [b, a], locale: english) == ParkSpotlight.entries(for: [a, b], locale: english))
        #expect(ParkSpotlight.entries(for: [b, a], locale: english).map(\.title) == ["A", "B"])
    }

    @Test func tappedIdentifierGivesTheParkBack() throws {
        for parkID in ["project-7", "wet-n-wild-alphen"] {
            let entry = try #require(ParkSpotlight.entries(for: [park(id: parkID)], locale: english).first)
            #expect(ParkSpotlight.parkID(fromIdentifier: entry.identifier) == parkID)
        }
    }

    @Test func otherIdentifiersAreNotParks() {
        for identifier in ["", "project-7", "rppl://session/s1", "rppl://parks/favorites", "https://park/project-7"] {
            #expect(ParkSpotlight.parkID(fromIdentifier: identifier) == nil, "\(identifier)")
        }
    }

    @Test func fingerprintFollowsTheContent() throws {
        let base = ParkSpotlight.entries(for: [park(shortName: "P7")], locale: english)
        let entry = try #require(base.first)
        #expect(ParkSpotlight.fingerprint(of: base) == ParkSpotlight.fingerprint(of: base))

        var renamed = entry
        renamed.title = "Other"
        var moved = entry
        moved.latitude += 0.001
        var retagged = entry
        retagged.keywords.append("new")
        var resubtitled = entry
        resubtitled.subtitle = nil

        let fingerprints = Set([base, [renamed], [moved], [retagged], [resubtitled]].map(ParkSpotlight.fingerprint(of:)))
        #expect(fingerprints.count == 5)
    }

    @Test func fingerprintOfNoParksIsStillAFingerprint() {
        #expect(ParkSpotlight.fingerprint(of: []).count == 64)
    }

    @Test func fingerprintFitsTheClientState() {
        let many = (0..<500).map { park(id: "park-\($0)", name: "Park \($0)") }
        let fingerprint = ParkSpotlight.fingerprint(of: ParkSpotlight.entries(for: many, locale: english))
        #expect(fingerprint.utf8.count <= 250)
    }

    @Test func bundledParksAllGetAnEntry() {
        let parks = ParkCatalog.load(userRoot: nil)
        let entries = ParkSpotlight.entries(for: parks, locale: english)
        #expect(!entries.isEmpty)
        #expect(entries.count == parks.filter(\.isListed).count)
        #expect(Set(entries.map(\.identifier)).count == entries.count)
        for entry in entries {
            #expect(ParkSpotlight.parkID(fromIdentifier: entry.identifier) != nil, "\(entry.identifier)")
        }
    }
}
