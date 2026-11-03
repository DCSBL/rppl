import Foundation
import Testing
@testable import RpplCore

struct ParkEventReaderTests {
    private static let today = "2026-11-03"

    private func page(_ text: String, url: String = "https://park.example/agenda", heading: String = "Agenda") -> ParkSourcePage {
        ParkSourcePage(url: url, title: "Park", blocks: [ParkSourceBlock(heading: heading, text: text)])
    }

    @Test func readsDutchGermanAndEnglishDates() {
        let found = ParkEventReader.read([page("""
        12 december 2026 Kerstborrel
        Sa 16. Januar 2027: Wake Battle
        December 20, 2026 Open Day
        """)], today: Self.today)
        let starts = found.map { ParkEventReader.start($0.exception) }
        #expect(starts == ["2026-12-12", "2026-12-20", "2027-01-16"])
        #expect(found.first?.exception.label == "Kerstborrel")
        #expect(found.first?.exception.kind == ParkExceptionKind.event)
        #expect(found.first?.exception.dates == ["2026-12-12"])
    }

    @Test func readsRangesAndNumericDates() {
        let found = ParkEventReader.read([page("""
        10 t/m 12 december 2026 Wake Camp
        24-12-2026 Gesloten
        """)], today: Self.today)
        let camp = found.first { $0.exception.label == "Wake Camp" }
        #expect(camp?.exception.from == "2026-12-10")
        #expect(camp?.exception.until == "2026-12-12")
        #expect(camp?.exception.dates == nil)
        let closed = found.first { $0.exception.label == "Gesloten" }
        #expect(closed?.exception.kind == ParkExceptionKind.closed)
        #expect(closed?.exception.dates == ["2026-12-24"])
    }

    @Test func pastDatesAndDatesWithoutYearInThePastAreLeftOut() {
        let found = ParkEventReader.read([page("""
        1 oktober 2026 Oude wedstrijd
        5 maart Zonder jaar
        20 december Dit jaar
        """)], today: Self.today)
        #expect(found.map { $0.exception.label } == ["Dit jaar"])
        #expect(found.first?.exception.dates == ["2026-12-20"])
    }

    @Test func impossibleDatesAreLeftOut() {
        #expect(ParkEventReader.read([page("31 februari 2027 Nooit")], today: Self.today).isEmpty)
    }

    @Test func nameComesFromThePreviousLineWhenTheDateStandsAlone() {
        let found = ParkEventReader.read([page("Wake Battle\n10 december 2026")], today: Self.today)
        #expect(found.first?.exception.label == "Wake Battle")
    }

    @Test func pagesThatAreNotAboutEventsAreIgnored() {
        let other = page("12 december 2026 Kerstborrel", url: "https://park.example/prijzen", heading: "Prijzen")
        #expect(ParkEventReader.read([other], today: Self.today).isEmpty)
        let heading = page("12 december 2026 Kerstborrel", url: "https://park.example/", heading: "Evenementen")
        #expect(ParkEventReader.read([heading], today: Self.today).count == 1)
    }

    @Test func timesAndPricesAreNotDates() {
        #expect(ParkEventReader.read([page("Open 10.30 - 18.00 uur\nDagkaart 12.50")], today: Self.today).isEmpty)
    }

    @Test func itemsAddExceptionsAndSkipKnownOnes() throws {
        let found = ParkEventReader.read([page("12 december 2026 Kerstborrel")], today: Self.today)
        var candidates = ParkImportCandidates()
        candidates.events = found
        var park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 1, lon: 1))
        let items = ParkImportMerge.items(from: candidates, in: park, grounding: ParkImportGrounding(sourceText: ""))
        let item = try #require(items.first { $0.field == .events })
        #expect(item.title == "Kerstborrel · 2026-12-12")
        #expect(item.detail == "12 december 2026 Kerstborrel")
        park = ParkImportMerge.apply([item], to: park)
        #expect(park.opening?.exceptions?.count == 1)
        let again = ParkImportMerge.items(from: candidates, in: park, grounding: ParkImportGrounding(sourceText: ""))
        #expect(!again.contains { $0.field == .events })
        #expect(ParkImportMerge.apply([item], to: park).opening?.exceptions?.count == 1)
    }
}
