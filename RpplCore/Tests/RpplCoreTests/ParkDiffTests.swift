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
        edited.prices = [ParkPrice(name: "Day", price: "20")]
        edited.name = "New name"
        #expect(ParkDiff.changedSections(from: park(), to: edited) == [.basics, .contact, .prices])
    }

    @Test func lineDiffReportsRemovedAndAdded() {
        let diff = ParkDiff.lineDiff(from: "a\nb\nc", to: "a\nx\nc\nd")
        #expect(diff.removed == [.init(number: 2, text: "b")])
        #expect(diff.added == [.init(number: 2, text: "x"), .init(number: 4, text: "d")])
        #expect(diff.patchText == "-2: b\n+2: x\n+4: d")
        #expect(diff.summary(removedHeading: "Removed", addedHeading: "Added")
            == "Removed\nLine 2: b\n\nAdded\nLine 2: x\nLine 4: d")
    }

    @Test func lineDiffOfIdenticalTextIsEmpty() {
        #expect(ParkDiff.lineDiff(from: "a\nb", to: "a\nb").isEmpty)
    }

    @Test func locationAndCablesAreDetected() {
        var edited = park()
        edited.location = ParkCoordinate(lat: 3, lon: 4)
        edited.cables = [ParkCable(direction: .clockwise)]
        #expect(ParkDiff.changedSections(from: park(), to: edited) == [.location, .cables])
    }
}
