import Foundation
import Testing
@testable import RpplCore

struct ParkEditorLogicTests {
    // MARK: Links

    @Test func linkUpsertOverwritesSameKindInAnyCasing() {
        var links = [ParkLink(kind: "instagram", url: "https://instagram.com/a")]
        ParkLinkKinds.upsert(ParkLink(kind: "  Instagram ", url: "https://instagram.com/b"), into: &links)
        #expect(links == [ParkLink(kind: "  Instagram ", url: "https://instagram.com/b")])
        ParkLinkKinds.upsert(ParkLink(kind: "Team   shop", url: "https://shop.nl"), into: &links)
        ParkLinkKinds.upsert(ParkLink(kind: "team shop", url: "https://shop2.nl"), into: &links)
        #expect(links.count == 2)
        #expect(links[1].url == "https://shop2.nl")
    }

    @Test func linkKindsAreDetectedFromTheAddress() {
        #expect(ParkLinkKinds.detect(url: "https://www.instagram.com/park/") == ParkLinkKinds.instagram)
        #expect(ParkLinkKinds.detect(url: "instagr.am/p/x") == ParkLinkKinds.instagram)
        #expect(ParkLinkKinds.detect(url: "https://m.facebook.com/park") == ParkLinkKinds.facebook)
        #expect(ParkLinkKinds.detect(url: "https://youtu.be/abc") == ParkLinkKinds.youtube)
        #expect(ParkLinkKinds.detect(url: "https://www.tiktok.com/@park") == nil)
        #expect(ParkLinkKinds.detect(url: "https://notinstagram.com") == nil)
        #expect(ParkLinkKinds.detect(url: "https://park.nl") == nil)
        #expect(ParkLinkKinds.detect(url: "") == nil)
        #expect(ParkLinkKinds.isPreset(" Booking "))
        #expect(!ParkLinkKinds.isPreset("tripadvisor"))
        #expect(ParkLinkKinds.duplicateKinds(in: [
            ParkLink(kind: "Booking", url: "a"), ParkLink(kind: "booking ", url: "b"), ParkLink(kind: "", url: "c"),
        ]) == ["booking"])
    }

    // MARK: Days, months, time

    @Test func daysCollapseToTheShortestSelector() {
        #expect(ParkDaySelection.tokens(from: Set(ParkDaySelection.weekdayTokens)) == nil)
        #expect(ParkDaySelection.tokens(from: []) == nil)
        #expect(ParkDaySelection.tokens(from: ["mon", "tue", "wed", "thu", "fri"]) == ["weekdays"])
        #expect(ParkDaySelection.tokens(from: ["sat", "sun"]) == ["weekend"])
        #expect(ParkDaySelection.tokens(from: ["mon", "tue", "wed", "thu", "fri", "sat"]) == ["weekdays", "sat"])
        #expect(ParkDaySelection.tokens(from: ["wed", "fri", "sun"]) == ["wed", "fri", "sun"])
        #expect(ParkDaySelection.tokens(from: ["sun", "mon", "nonsense"]) == ["mon", "sun"])
    }

    @Test func daysExpandBack() {
        #expect(ParkDaySelection.days(from: nil) == Set(ParkDaySelection.weekdayTokens))
        #expect(ParkDaySelection.days(from: ["daily"]) == Set(ParkDaySelection.weekdayTokens))
        #expect(ParkDaySelection.days(from: ["weekdays", "SAT"]) == ["mon", "tue", "wed", "thu", "fri", "sat"])
        #expect(ParkDaySelection.days(from: ["weekend", "bogus"]) == ["sat", "sun"])
    }

    @Test func monthsRoundTrip() {
        #expect(ParkDaySelection.months(from: []) == nil)
        #expect(ParkDaySelection.months(from: Set(1...12)) == nil)
        #expect(ParkDaySelection.months(from: [9, 4, 13, 0]) == [4, 9])
        #expect(ParkDaySelection.monthSet(from: nil) == Set(1...12))
        #expect(ParkDaySelection.monthSet(from: [4, 9, 20]) == [4, 9])
    }

    @Test func clockTimesAre24HourText() {
        #expect(ParkClock.minutes("14:30") == 870)
        #expect(ParkClock.minutes("sunset") == 1440)
        #expect(ParkClock.minutes("SUNSET") == 1440)
        #expect(ParkClock.minutes("2:30 PM") == nil)
        #expect(ParkClock.text(minutes: 870) == "14:30")
        #expect(ParkClock.text(minutes: 1440) == "00:00")
        #expect(ParkClock.text(minutes: -60) == "23:00")
        #expect(ParkClock.wrapsPastMidnight(open: "22:00", close: "02:00"))
        #expect(!ParkClock.wrapsPastMidnight(open: "10:00", close: "18:00"))
        #expect(!ParkClock.wrapsPastMidnight(open: "17:00", close: "sunset"))
    }

    @Test func calendarDatesAreDaysInUTC() throws {
        let date = try #require(ParkDateText.date(from: "2026-10-04"))
        #expect(ParkDateText.iso(from: date) == "2026-10-04")
        #expect(ParkDateText.iso(from: date.addingTimeInterval(11 * 3600)) == "2026-10-04")
        #expect(ParkDateText.date(from: "2026-02-31") == nil)
        #expect(ParkDateText.date(from: "2026-2-3") == nil)
        #expect(ParkDateText.date(from: "tomorrow") == nil)
        #expect(ParkDateText.isValid("2028-02-29"))
        #expect(!ParkDateText.isValid("2027-02-29"))
    }

    @Test func tracedWindingFollowsTravelOrder() {
        // North-up map: east is +lon, north is +lat. A -> B (east) -> C (south-east) -> D (south): clockwise.
        let clockwise = ParkCable(points: [
            ParkCablePoint(lat: 52.002, lon: 4.000), ParkCablePoint(lat: 52.002, lon: 4.004),
            ParkCablePoint(lat: 52.000, lon: 4.004), ParkCablePoint(lat: 52.000, lon: 4.000),
        ])
        #expect(clockwise.tracedWindingIsClockwise == true)
        var reversed = clockwise
        reversed.points?.reverse()
        #expect(reversed.tracedWindingIsClockwise == false)
        #expect(ParkCable(points: Array(clockwise.points!.prefix(2))).tracedWindingIsClockwise == nil)
        #expect(ParkCable().tracedWindingIsClockwise == nil)
        let line = ParkCable(points: [
            ParkCablePoint(lat: 52, lon: 4), ParkCablePoint(lat: 52, lon: 4.001), ParkCablePoint(lat: 52, lon: 4.002),
        ])
        #expect(line.tracedWindingIsClockwise == nil)
    }

    // MARK: Validation

    private func base() -> Park {
        Park(id: "p", name: "Park", location: ParkCoordinate(lat: 52, lon: 4))
    }

    @Test func validationFlagsMalformedValuesNotEmptyOnes() {
        var park = base()
        #expect(ParkDraft.validate(park).isEmpty)
        park.phone = "x"
        park.email = "nope"
        park.website = "not a site"
        #expect(ParkDraft.validate(park) == [.invalidPhone, .invalidEmail, .invalidWebsite])
        park.phone = "+31 10 260 0110"
        park.email = "info@park.nl"
        park.website = "park.nl"
        #expect(ParkDraft.validate(park).isEmpty)
    }

    @Test func validationCoversPricesLinksAndTimes() {
        var park = base()
        park.prices = [
            ParkPrice(name: "", options: [ParkPriceOption(amount: "5")]),
            ParkPrice(name: "Day pass", options: [ParkPriceOption(per: "per day")]),
        ]
        park.links = [ParkLink(kind: "", url: "https://a.nl"), ParkLink(kind: "x", url: ""), ParkLink(kind: "y", url: "no site")]
        park.opening = ParkOpening(
            rules: [ParkOpeningRule(open: "9am", close: "18:00")],
            slots: [ParkSlot(id: "1", start: "10:00", end: "x")]
        )
        let issues = ParkDraft.validate(park)
        #expect(issues == [
            .priceNeedsName(index: 0), .priceNeedsAmount(index: 1),
            .linkNeedsKind(index: 0), .linkNeedsAddress(index: 1), .invalidLinkAddress(index: 2),
            .invalidTime(rule: 0), .invalidBlockTime(block: 0),
        ])
        #expect(Set(issues.map(\.section)) == [.prices, .links, .opening])
        #expect(ParkDraft.Issue.missingName.section == .basics)
        #expect(ParkDraft.Issue.invalidLocation.section == .location)
        #expect(ParkDraft.Issue.cableTooShort(index: 0).section == .cables)
        #expect(ParkDraft.Issue.invalidEmail.section == .contact)
    }

    @Test func filledSectionsMatchWhatIsThere() {
        var park = base()
        park.location = ParkCoordinate(lat: 0, lon: 0)
        for section in ParkSection.allCases where section != .basics {
            #expect(!ParkDraft.isFilled(section, in: park), "\(section)")
        }
        #expect(ParkDraft.isFilled(.basics, in: park))
        park.location = ParkCoordinate(lat: 52, lon: 4)
        park.phone = "010"
        park.facilities = ["Showers"]
        park.cables = [ParkCable()]
        park.prices = [ParkPrice(name: "A")]
        park.links = [ParkLink(kind: "a", url: "b")]
        park.opening = ParkOpening(booking: "required")
        #expect(!ParkDraft.isFilled(.opening, in: park)) // only a booking mode: still no times
        park.opening = ParkOpening(rules: [ParkOpeningRule(open: "09:00", close: "18:00")])
        for section in ParkSection.allCases {
            #expect(ParkDraft.isFilled(section, in: park), "\(section)")
        }
    }

    @Test func finalizedTidiesEverythingTheEditorLeavesLoose() {
        var park = base()
        park.name = "  Park  North "
        park.author = "   "
        park.website = "park.nl"
        park.facilities = [" Showers ", "showers", "", "Bar"]
        park.cables = [ParkCable(name: "  ", description: " \n ", lengthM: 0)]
        park.prices = [
            ParkPrice(name: "", options: [ParkPriceOption()]),
            ParkPrice(name: " Day  pass ", options: [
                ParkPriceOption(amount: " 25,00 ", currency: "eur", per: " per  day ", note: " "),
                ParkPriceOption(),
            ]),
        ]
        park.links = [
            ParkLink(kind: " ", url: " "), ParkLink(kind: "Instagram", url: "instagram.com/a"),
            ParkLink(kind: "instagram", url: "instagram.com/b"),
        ]
        park.opening = ParkOpening(
            booking: nil,
            rules: [ParkOpeningRule(label: " ", open: "09:00", close: "18:00", note: "")],
            slots: []
        )
        let result = ParkDraft.finalized(park)
        #expect(result.name == "Park North")
        #expect(result.author == nil)
        #expect(result.website == "https://park.nl")
        #expect(result.facilities == ["Showers", "Bar"])
        #expect(result.cables == [ParkCable()])
        #expect(result.prices == [ParkPrice(name: "Day pass", options: [ParkPriceOption(amount: "25", currency: "EUR", per: "per day")])])
        #expect(result.links == [ParkLink(kind: "instagram", url: "https://instagram.com/b")])
        #expect(result.opening?.rules?.first?.label == nil)
        #expect(result.opening?.rules?.first?.note == nil)
        #expect(result.opening?.slots == nil)
    }

    @Test func finalizedTidiesSelectorsOfHoursAndBlocks() {
        var park = base()
        park.opening = ParkOpening(
            rules: [ParkOpeningRule(
                months: [], days: [], dates: ["2026-12-25", "nope", "2026-12-24", "2026-12-25", "2026-02-31"],
                open: "10:00", close: "18:00"
            )],
            slots: [ParkSlot(id: "1", months: [4], days: ["sat"], dates: ["bad"], start: "10:00", end: "11:00")]
        )
        let rule = ParkDraft.finalized(park).opening?.rules?.first
        #expect(rule?.months == nil)
        #expect(rule?.days == nil)
        #expect(rule?.dates == ["2026-12-24", "2026-12-25"])
        let slot = ParkDraft.finalized(park).opening?.slots?.first
        #expect(slot?.months == [4])
        #expect(slot?.days == ["sat"])
        #expect(slot?.dates == nil)
    }

    @Test func finalizedDropsAnOpeningWithNothingInIt() {
        var park = base()
        park.opening = ParkOpening(booking: nil, rules: [], slots: [])
        #expect(ParkDraft.finalized(park).opening == nil)
        park.opening = ParkOpening(booking: "required")
        #expect(ParkDraft.finalized(park).opening?.booking == "required")
        park.opening = ParkOpening(exceptions: [ParkOpeningException(kind: "closed", dates: ["2026-10-10"])])
        #expect(ParkDraft.finalized(park).opening?.exceptions?.count == 1)
    }

    @Test func finalizedCapsRunawayLists() {
        var park = base()
        park.facilities = (0..<100).map { "Facility \($0)" }
        park.links = (0..<50).map { ParkLink(kind: "link \($0)", url: "https://a.nl/\($0)") }
        let result = ParkDraft.finalized(park)
        #expect(result.facilities?.count == ParkLimits.facilities)
        #expect(result.links?.count == ParkLimits.links)
    }

    // MARK: Unknown opening times

    @Test func noOpeningTimesFilledInIsUnknownNotClosed() {
        let noon = Date(timeIntervalSince1970: 1_790_000_000)
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var park = base()
        #expect(park.schedule(on: noon).isScheduleKnown == false)
        #expect(park.openStatus(at: noon) == .unknown)
        park.opening = ParkOpening(booking: "required", note: "Call first")
        #expect(park.schedule(on: noon).isScheduleKnown == false)
        #expect(park.openStatus(at: noon) == .unknown)
        #expect(ParkSchedule.day(for: park.opening, on: noon, timeZone: zone).isOpen == false)
        park.opening = ParkOpening(rules: [ParkOpeningRule(open: "00:00", close: "23:59")])
        #expect(park.schedule(on: noon).isScheduleKnown)
        #expect(park.opening?.isScheduleKnown == true)
    }

    @Test func unknownParksStayInTheOpenOnDateFilter() {
        let park = base()
        let filters = ParkFilters(openOnDate: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(ParkListing.filtered([park], favorites: [], filters: filters) == [park])
    }

    // MARK: Drafts

    private func tempStore() -> ParkDraftStore {
        ParkDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("drafts-\(UUID().uuidString)"))
    }

    @Test func draftsSurviveARoundTripIncompleteAsTheyAre() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var park = Park(id: "", name: "", location: ParkCoordinate(lat: 0, lon: 0))
        park.prices = [ParkPrice(name: "Half done")]
        let draft = ParkEditDraft(id: ParkEditDraft.newID(), park: park, step: 3, savedAt: Date(timeIntervalSince1970: 1_790_000_000))
        try store.save(draft)
        #expect(store.load(id: draft.id) == draft)
        #expect(store.all() == [draft])
        store.delete(id: draft.id)
        #expect(store.load(id: draft.id) == nil)
        #expect(store.all().isEmpty)
    }

    @Test func draftsListNewestFirstAndSkipBrokenFiles() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 1, lon: 2))
        let old = ParkEditDraft(id: "new-a", park: park, savedAt: Date(timeIntervalSince1970: 1_000))
        let fresh = ParkEditDraft(id: ParkEditDraft.editID(forPark: "Project 7/../x"), editsParkID: "p", park: park, savedAt: Date(timeIntervalSince1970: 2_000))
        try store.save(old)
        try store.save(fresh)
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("broken.json"))
        // A copy under another name must not shadow the original.
        try FileManager.default.copyItem(
            at: store.directory.appendingPathComponent("new-a.json"),
            to: store.directory.appendingPathComponent("new-b.json")
        )
        #expect(store.all().map(\.id) == [fresh.id, old.id])
        #expect(fresh.id == "edit-project-7----x")
    }

    @Test func draftIDsCannotEscapeTheFolder() {
        let store = tempStore()
        let park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 1, lon: 2))
        #expect(throws: (any Error).self) { try store.save(ParkEditDraft(id: "../evil", park: park)) }
        #expect(throws: (any Error).self) { try store.save(ParkEditDraft(id: "", park: park)) }
        #expect(store.load(id: "../evil") == nil)
        #expect(ParkEditDraft(id: "x", park: park).title == "P")
        #expect(ParkEditDraft(id: "x", park: Park(id: "", name: "  ", location: ParkCoordinate(lat: 0, lon: 0))).title.isEmpty)
    }
}
