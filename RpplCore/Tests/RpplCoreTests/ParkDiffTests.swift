import Testing
@testable import RpplCore

struct ParkDiffTests {
    private func park(id: String = "p") -> Park {
        Park(id: id, name: "Park", location: ParkCoordinate(lat: 1, lon: 2), timezone: "Europe/Amsterdam")
    }

    @Test func noChangesReportsNoSections() {
        let park = park()
        #expect(ParkDiff.changedSections(from: park, to: park).isEmpty)
    }

    @Test func nameChangeReportsBasics() {
        var edited = park()
        edited.name = "New name"
        #expect(ParkDiff.changedSections(from: park(), to: edited) == [.basics])
    }

    @Test func multipleSectionsReportInDeclarationOrder() {
        var edited = park()
        edited.phone = "+31 6 12345678"
        edited.prices = [ParkPrice(name: "Day", options: [ParkPriceOption(amount: "20", currency: "EUR")])]
        edited.name = "New name"
        #expect(ParkDiff.changedSections(from: park(), to: edited) == [.basics, .contact, .prices])
    }

    @Test func locationAndCablesAreDetected() {
        var edited = park()
        edited.location = ParkCoordinate(lat: 3, lon: 4)
        edited.cables = [ParkCable(direction: .clockwise)]
        #expect(ParkDiff.changedSections(from: park(), to: edited) == [.location, .cables])
    }
}
