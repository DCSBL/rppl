import Foundation
import Testing
@testable import RpplCore

struct ParksTests {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    private func date(_ iso: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    private func date(_ iso: String, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute)
        )!
    }

    private func project7() throws -> Park {
        let park = ParkCatalog.loadBundled().first { $0.id == "project7-rotterdam" }
        return try #require(park)
    }

    @Test func bundledProject7Decodes() throws {
        let park = try project7()
        #expect(park.name == "Project 7 Cablepark Rotterdam")
        #expect(park.location.lat == 51.979207)
        #expect(park.cables?.count == 1)
        #expect(park.cables?.first?.direction == .clockwise)
        #expect(park.cables?.first?.points?.count == 5)
        #expect(park.opening?.slots?.count == 7)
    }

    @Test func project7SeptemberWeekdayOffersBlocks3To6() throws {
        // 2026-09-24 is a Thursday.
        let day = try project7().schedule(on: date("2026-09-24"))
        #expect(day.windows.map { ParkSchedule.timeText(minutes: $0.startMinute) } == ["14:00"])
        #expect(day.windows.map { ParkSchedule.timeText(minutes: $0.endMinute) } == ["20:00"])
        #expect(day.availableSlots.map(\.id) == ["3", "4", "5", "6"])
    }

    @Test func project7SeptemberWeekendAddsBlock2() throws {
        // 2026-09-26 is a Saturday.
        let day = try project7().schedule(on: date("2026-09-26"))
        #expect(day.availableSlots.map(\.id) == ["2", "3", "4", "5", "6"])
    }

    @Test func project7ClosedInWinterAndAprilWeekdays() throws {
        let park = try project7()
        #expect(park.schedule(on: date("2026-01-14")).isOpen == false)
        #expect(park.schedule(on: date("2026-04-15")).isOpen == false)
        #expect(park.schedule(on: date("2026-10-07")).isOpen == false)
    }

    @Test func openStatusReflectsTimeOfDayNotJustTheDate() throws {
        let park = try project7()
        // 2026-09-24 is a Thursday, open 14:00-20:00; Friday 09-25 is also a weekday (open).
        #expect(park.openStatus(at: date("2026-09-24", hour: 10)) == .openToday)
        #expect(park.openStatus(at: date("2026-09-24", hour: 15)) == .openToday)
        // Past today's close, but tomorrow is open too: must not still read as "open".
        #expect(park.openStatus(at: date("2026-09-24", hour: 21)) == .opensTomorrow)
        // 2026-10-02 is a Friday: October only opens weekends, so today's closed but Saturday isn't.
        #expect(park.openStatus(at: date("2026-10-02", hour: 12)) == .opensTomorrow)
        // 2026-10-05 is a Monday, 10-06 a Tuesday: both closed (October is weekend-only).
        #expect(park.openStatus(at: date("2026-10-05", hour: 12)) == .closed)
        // No opening times filled in is unknown, never closed.
        #expect(Park(id: "x", name: "X", location: ParkCoordinate(lat: 0, lon: 0)).openStatus() == .unknown)
    }

    @Test func openStatusDetailCarriesTheRelevantWindow() throws {
        let park = try project7()
        // Before the 14:00-20:00 window: window is set but hasn't started yet.
        let notYetOpen = park.openStatusDetail(at: date("2026-09-24", hour: 10))
        #expect(notYetOpen.status == .openToday)
        #expect(notYetOpen.window?.startMinute == 14 * 60)
        #expect(notYetOpen.window?.endMinute == 20 * 60)
        #expect(notYetOpen.windowHasStarted == false)

        // Inside the window: same window, but already started.
        let alreadyOpen = park.openStatusDetail(at: date("2026-09-24", hour: 15))
        #expect(alreadyOpen.status == .openToday)
        #expect(alreadyOpen.window?.endMinute == 20 * 60)
        #expect(alreadyOpen.windowHasStarted == true)

        // Opens tomorrow / closed: no window to show, it's not "today"'s.
        #expect(park.openStatusDetail(at: date("2026-09-24", hour: 21)).window == nil)
        #expect(park.openStatusDetail(at: date("2026-10-05", hour: 12)).window == nil)
    }

    @Test func monthsCollapseToOneEntryPerMonth() throws {
        let months = ParkSchedule.months(for: try project7().opening)
        #expect(months.map(\.month) == [4, 5, 6, 7, 8, 9, 10])
        let september = try #require(months.first { $0.month == 9 })
        #expect(september.lines.map(\.days) == [["weekdays"], ["weekend"]])
        #expect(september.lines.map(\.open) == ["14:00", "12:30"])
        let july = try #require(months.first { $0.month == 7 })
        #expect(july.lines.count == 1)
    }

    @Test func rulesWithoutMonthsGoInTrailingEntry() {
        let opening = ParkOpening(rules: [
            ParkOpeningRule(months: [2], open: "10:00", close: "11:00"),
            ParkOpeningRule(open: "12:00", close: "13:00"),
            ParkOpeningRule(months: [1, 2], open: "14:00", close: "15:00"),
        ])
        let months = ParkSchedule.months(for: opening)
        #expect(months.map(\.month) == [1, 2, nil])
        #expect(months[1].lines.map(\.open) == ["10:00", "14:00"])
    }

    @Test func bundledProject7HasBookingLink() throws {
        let link = try #require(try project7().links?.first { $0.kind == "booking" })
        #expect(link.url == "https://www.project7cablepark.nl/online-ticket/")
    }

    @Test func bundledWetNWildHasBeginnerHourAndCcwCable() throws {
        let park = try #require(ParkCatalog.loadBundled().first { $0.id == "wetnwild-alphen" })
        #expect(park.cables?.first?.direction == .counterClockwise)
        #expect(park.cables?.first?.points?.count == 5)
        // 2026-09-26 is a Saturday: full window plus the beginner hour.
        let saturday = park.schedule(on: date("2026-09-26"))
        #expect(saturday.windows.count == 2)
        #expect(saturday.windows.contains { $0.note == "Cable runs at 27 km/h" })
        // 2026-09-27 is a Sunday.
        #expect(park.schedule(on: date("2026-09-27")).windows.map(\.startMinute) == [13 * 60])
        #expect(park.schedule(on: date("2026-09-28")).isOpen == false)
        // Hourly, unnumbered blocks that fit the day's window; Wed 2026-09-23, Thu 09-24, Sat 09-26.
        #expect(park.opening?.numbered == false)
        #expect(park.opening?.bookingMinutes == [60, 120])
        #expect(park.schedule(on: date("2026-09-23")).availableSlots.map(\.start) == ["16:00", "17:00", "18:00", "19:00"])
        #expect(park.schedule(on: date("2026-09-24")).availableSlots.map(\.start) == ["17:00", "18:00", "19:00"])
        #expect(saturday.availableSlots.map(\.start) == ["12:00", "13:00", "14:00", "15:00", "16:00", "17:00"])
        #expect(park.links?.first { $0.kind == "booking" } != nil)
    }

    @Test func lastUpdatedParsesDateOnlyString() throws {
        let park = try ParkCatalog.parse(yaml: """
            version: 1
            id: p
            name: P
            updated_at: 2026-09-26
            location:
              lat: 52.0
              lon: 5.0
            """, fallbackId: "p")
        let updated = try #require(park.lastUpdated)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        let parts = calendar.dateComponents([.year, .month, .day], from: updated)
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 26)
        #expect(Park(id: "x", name: "X", location: ParkCoordinate(lat: 0, lon: 0)).lastUpdated == nil)
    }

    @Test func specialDatesOverrideAndGroupUnderTheirMonth() throws {
        let yaml = """
        version: 1
        id: holiday
        name: Holiday
        location: { lat: 52.0, lon: 4.0 }
        opening:
          rules:
            - { label: Easter, dates: ["2026-04-05", "2026-04-06"], open: "12:30", close: "17:00" }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(park.schedule(on: date("2026-04-05")).isOpen)
        #expect(park.schedule(on: date("2026-04-07")).isOpen == false)
        let months = ParkSchedule.months(for: park.opening)
        #expect(months.map(\.month) == [4])
        #expect(months.first?.lines.first?.dates == ["2026-04-05", "2026-04-06"])
    }

    @Test func bundledDownUnderDecodesWithoutOpeningBlock() throws {
        let park = try #require(ParkCatalog.loadBundled().first { $0.id == "downunder-nieuwegein" })
        #expect(park.cables?.count == 2)
        #expect(park.cables?.first?.direction == .counterClockwise)
        #expect(park.cables?.first?.effectiveLengthM == 720)
        #expect(park.cables?.first?.points?.count == 5)
        #expect(park.prices?.count == 5)
        #expect(park.links?.contains { $0.kind == "booking" } == true)
        // 2026-09-24 Thursday 17-20, 09-23 Wednesday 15-20, 09-28 Monday closed, 09-26 Saturday 12-19.
        #expect(park.schedule(on: date("2026-09-24")).availableSlots.map(\.start) == ["17:00", "18:00", "19:00"])
        #expect(park.schedule(on: date("2026-09-23")).availableSlots.count == 5)
        #expect(park.schedule(on: date("2026-09-28")).isOpen == false)
        #expect(park.schedule(on: date("2026-09-26")).availableSlots.count == 7)
        #expect(park.schedule(on: date("2026-07-14")).availableSlots.count == 8)
    }

    @Test func project7JulyOpensAllBlocks() throws {
        let day = try project7().schedule(on: date("2026-07-15"))
        #expect(day.availableSlots.count == 7)
    }

    @Test func dropInOnlyParkWithDatedRuleChange() throws {
        let yaml = """
        version: 1
        id: drop-in
        name: Drop In
        location: { lat: 52.0, lon: 4.0 }
        opening:
          booking: none
          rules:
            - { label: Summer, until: "2026-10-04", days: [wed], open: "16:00", close: "20:00" }
            - { label: Beginner hour, days: [sat], open: "12:00", close: "13:00", note: "27 km/h" }
            - { days: [sat], open: "12:00", close: "18:00" }
            - { label: Autumn, from: "2026-10-05", days: [wed], open: "17:00", close: "19:00" }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        let summerWed = park.schedule(on: date("2026-09-30"))
        #expect(summerWed.windows.count == 1)
        #expect(summerWed.windows.first?.startMinute == 16 * 60)
        #expect(summerWed.availableSlots.isEmpty)
        let autumnWed = park.schedule(on: date("2026-10-07"))
        #expect(autumnWed.windows.first?.startMinute == 17 * 60)
        let saturday = park.schedule(on: date("2026-09-26"))
        #expect(saturday.windows.count == 2)
        #expect(saturday.windows.first?.note == "27 km/h")
    }

    @Test func overnightRuleWrapsPastMidnightOnTheSameDay() throws {
        let yaml = """
        version: 1
        id: overnight
        name: Overnight
        location: { lat: 52.0, lon: 4.0 }
        opening:
          rules:
            - { days: [fri], open: "22:00", close: "02:00" }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        // 2026-09-25 is a Friday: the window is stored as 22:00-26:00 (past-midnight close).
        let friday = park.schedule(on: date("2026-09-25"))
        #expect(friday.windows.map(\.startMinute) == [22 * 60])
        #expect(friday.windows.map(\.endMinute) == [26 * 60])
        // Before 22:00, the window hasn't started yet today but still counts as "open today".
        #expect(park.openStatus(at: date("2026-09-25", hour: 10)) == .openToday)
        #expect(park.openStatus(at: date("2026-09-25", hour: 23)) == .openToday)
        // Saturday has no matching rule of its own — a session started Friday night that runs
        // past midnight isn't tracked as "still open" once the calendar day rolls over.
        #expect(park.schedule(on: date("2026-09-26")).isOpen == false)
    }

    @Test func blocksOnlyParkWithoutRules() throws {
        let yaml = """
        version: 1
        id: blocks
        name: Blocks
        location: { lat: 52.0, lon: 4.0 }
        opening:
          slots:
            - { id: a, days: [sat, sun], start: "10:00", end: "11:00" }
            - { id: b, start: "11:00", end: "12:00" }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(park.schedule(on: date("2026-09-26")).availableSlots.map(\.id) == ["a", "b"])
        #expect(park.schedule(on: date("2026-09-24")).availableSlots.map(\.id) == ["b"])
    }

    @Test func noRulesOrSlotsMeansUnknownAndTheOldHoursUnknownKeyIsIgnored() throws {
        let yaml = """
        version: 1
        id: unknown-hours
        name: Unknown
        location: { lat: 52.0, lon: 4.0 }
        opening:
          hours_unknown: true
          booking: required
          note: Call first
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        let day = park.schedule(on: date("2026-09-24"))
        #expect(day.isScheduleKnown == false)
        #expect(day.isOpen == false)
        #expect(day.availableSlots.isEmpty)
        #expect(park.openStatus(at: date("2026-09-24", hour: 10)) == .unknown)
        #expect(try !ParkCatalog.encode(park).contains("hours_unknown"))
    }

    @Test func blocksAloneMakeTheScheduleKnown() throws {
        let yaml = """
        version: 1
        id: blocks-only
        name: Blocks
        location: { lat: 52.0, lon: 4.0 }
        opening:
          slots:
            - { id: a, days: [thu], start: "10:00", end: "11:00" }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(park.schedule(on: date("2026-09-24")).availableSlots.map(\.id) == ["a"]) // Thursday
        #expect(park.schedule(on: date("2026-09-25")).isScheduleKnown)
        #expect(park.schedule(on: date("2026-09-25")).isOpen == false)
    }

    @Test func bundledWollebrandHasSeasonalHours() throws {
        let park = ParkCatalog.loadBundled().first { $0.id == "wollebrand-honselersdijk" }
        let park2 = try #require(park)
        #expect(park2.opening?.slots?.count == 6)
        // Friday 25 September 2026: rule is wed/fri 15:30-20:00.
        let day = park2.schedule(on: date("2026-09-25"))
        #expect(day.isScheduleKnown == true)
        #expect(day.isOpen == true)
        #expect(park2.openStatus(at: date("2026-09-25", hour: 15)) == .openToday)
    }

    @Test func minimalParkAndOptionalCablePoints() throws {
        let yaml = """
        version: 1
        id: bare
        name: Bare
        location: { lat: 1, lon: 2 }
        cables:
          - { name: Beginner, direction: "2.0", length_m: 320, description: Short }
          - { direction: custom-loop }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(park.opening == nil)
        #expect(park.cables?.first?.effectiveLengthM == 320)
        #expect(park.cables?.first?.direction == .twoPointZero)
        #expect(park.cables?.last?.direction?.rawValue == "custom-loop")
        #expect(park.cables?.last?.effectiveLengthM == nil)
        #expect(park.schedule().isOpen == false)
    }

    @Test func startPointsDefaultToFirstAndHonourFlags() {
        let a = ParkCablePoint(lat: 1, lon: 1)
        let b = ParkCablePoint(lat: 2, lon: 2, start: true)
        #expect(ParkCable(points: [a, b]).startPoints == [b])
        #expect(ParkCable(points: [a, ParkCablePoint(lat: 2, lon: 2)]).startPoints == [a])
        #expect(ParkCable().startPoints.isEmpty)
    }

    @Test func startBearingPointsTowardSecondPoint() throws {
        let cable = try #require(try project7().cables?.first)
        let start = try #require(cable.starts.first)
        let bearing = try #require(start.bearingDegrees)
        #expect(bearing > 60 && bearing < 75)
        #expect(ParkCable(points: [ParkCablePoint(lat: 1, lon: 1)]).starts.first?.bearingDegrees == nil)
    }

    @Test func loopCableLengthIncludesClosingSegment() throws {
        let cable = try #require(try project7().cables?.first)
        let open = try #require(cable.points).adjacentMeters
        let length = try #require(cable.computedLengthM)
        #expect(length > open)
        #expect(abs(open - 660.3) < 1)
        #expect(abs(length - 744.5) < 1)
        var twoPointZero = cable
        twoPointZero.direction = .twoPointZero
        #expect(twoPointZero.computedLengthM == open)
    }

    @Test func yamlRoundTrip() throws {
        let park = try project7()
        var decoded = try ParkCatalog.parse(yaml: try ParkCatalog.encode(park), fallbackId: "x")
        let original = try #require(park.cables?.first?.points)
        let roundTripped = try #require(decoded.cables?.first?.points)
        for (a, b) in zip(original, roundTripped) {
            #expect(abs(a.lat - b.lat) < 1e-9 && abs(a.lon - b.lon) < 1e-9)
        }
        // The encoder trims coordinate digits past double precision; compare the rest exactly.
        decoded.cables = park.cables
        #expect(decoded == park)
    }

    @Test func appWritesNativeBlockYAML() throws {
        // The editor's files and "Send to Rppl" mails reach scripts/validate_parks.py, which rejects
        // JSON-like `{ }` / `[ ]` collections (empty ones excepted).
        let flowCollection = "(?m)(^|: |- )[\\[{](?![\\]}]$)"
        for park in ParkCatalog.loadBundled() {
            let yaml = try ParkCatalog.encode(park)
            #expect(yaml.range(of: flowCollection, options: .regularExpression) == nil, "\(park.id) was written with flow style")
        }
    }

    @Test func userFileOverridesBundledById() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let yaml = "version: 1\nid: project7-rotterdam\nname: Edited\nlocation: { lat: 1, lon: 2 }\n"
        try yaml.write(to: dir.appendingPathComponent("edited.yaml"), atomically: true, encoding: .utf8)
        try "not: [valid".write(to: dir.appendingPathComponent("broken.yaml"), atomically: true, encoding: .utf8)
        let parks = ParkCatalog.load(userRoot: dir)
        #expect(parks.filter { $0.id == "project7-rotterdam" }.map(\.name) == ["Edited"])
    }

    @Test func nearestParkWithinRadius() {
        let a = Park(id: "a", name: "A", location: ParkCoordinate(lat: 52.0, lon: 4.0))
        let b = Park(id: "b", name: "B", location: ParkCoordinate(lat: 52.003, lon: 4.0))
        let near = ParkCoordinate(lat: 52.0025, lon: 4.0)
        #expect(ParkListing.nearest(to: near, in: [a, b])?.id == "b")
        #expect(ParkListing.nearest(to: ParkCoordinate(lat: 10, lon: 10), in: [a, b]) == nil)
    }

    @Test func sortingAndVisitCounts() {
        let near = Park(id: "near", name: "Near", location: ParkCoordinate(lat: 52.0, lon: 4.0))
        let far = Park(id: "far", name: "Far", location: ParkCoordinate(lat: 53.0, lon: 5.0))
        let fav = Park(id: "fav", name: "Zed", location: ParkCoordinate(lat: 54.0, lon: 6.0))
        let me = ParkCoordinate(lat: 52.001, lon: 4.001)
        let parks = [far, fav, near]
        let byDistance = ParkListing.sorted(parks, visits: [:], userLocation: me, sort: .distance)
        #expect(byDistance.map(\.id) == ["near", "far", "fav"])
        let byVisits = ParkListing.sorted(parks, visits: ["far": 3, "near": 1], userLocation: me, sort: .visits)
        #expect(byVisits.map(\.id) == ["far", "near", "fav"])
        let noFix = ParkListing.sorted(parks, visits: [:], userLocation: nil, sort: .distance)
        #expect(noFix.map(\.id) == ["far", "near", "fav"])

        let counts = ParkListing.visitCounts(
            parks: parks,
            sessionCenters: [me, ParkCoordinate(lat: 52.002, lon: 4.0), ParkCoordinate(lat: 10, lon: 10)]
        )
        #expect(counts == ["near": 2])
    }

    @Test func nearestAndVisitCountsMatchViaTracedCablePointsNotJustThePin() {
        // Pin is far away; a traced cable point is the close anchor instead.
        let cablePoint = ParkCoordinate(lat: 52.01, lon: 4.0)
        let park = Park(
            id: "a",
            name: "A",
            location: ParkCoordinate(lat: 53.0, lon: 5.0),
            cables: [ParkCable(points: [ParkCablePoint(lat: cablePoint.lat, lon: cablePoint.lon)])]
        )
        let near = ParkCoordinate(lat: 52.0105, lon: 4.0)
        #expect(ParkListing.nearest(to: near, in: [park])?.id == "a")
        #expect(ParkListing.visitCounts(parks: [park], sessionCenters: [near]) == ["a": 1])
    }

    @Test func filteringByFavoritesCableAndOpenDate() throws {
        let project7 = try project7()
        let wetNWild = try #require(ParkCatalog.loadBundled().first { $0.id == "wetnwild-alphen" })
        let parks = [project7, wetNWild]

        #expect(ParkFilters().isActive == false)

        let favoritesOnly = ParkFilters(favoritesOnly: true)
        #expect(favoritesOnly.isActive)
        #expect(ParkListing.filtered(parks, favorites: [], filters: favoritesOnly).isEmpty)
        #expect(
            ParkListing.filtered(parks, favorites: [wetNWild.id], filters: favoritesOnly).map(\.id)
                == [wetNWild.id]
        )

        let ccwOnly = ParkFilters(cableDirections: [.counterClockwise])
        #expect(ParkListing.filtered(parks, favorites: [], filters: ccwOnly).map(\.id) == [wetNWild.id])
        let cwOnly = ParkFilters(cableDirections: [.clockwise])
        #expect(ParkListing.filtered(parks, favorites: [], filters: cwOnly).map(\.id) == [project7.id])
        let twoPointZeroOnly = ParkFilters(cableDirections: [.twoPointZero])
        #expect(ParkListing.filtered(parks, favorites: [], filters: twoPointZeroOnly).isEmpty)

        // 2026-09-24 (Thursday) project7 is open; 2026-10-07 both are closed.
        let openThursday = ParkFilters(openOnDate: date("2026-09-24"))
        #expect(ParkListing.filtered(parks, favorites: [], filters: openThursday).map(\.id).contains(project7.id))
        let closedDay = ParkFilters(openOnDate: date("2026-10-07"))
        #expect(ParkListing.filtered(parks, favorites: [], filters: closedDay).isEmpty)

        // Cleared filters show everything, including closed parks.
        #expect(ParkListing.filtered(parks, favorites: [], filters: ParkFilters()).map(\.id) == parks.map(\.id))
    }

    // MARK: - Opening exceptions

    /// Wet 'n Wild's regular hours with the extra-hours week it announced for 2026-09-29 to 2026-10-01.
    /// The bundled file no longer carries those past exceptions, so the test adds them.
    private func wetNWild() throws -> Park {
        var park = try #require(ParkCatalog.loadBundled().first { $0.id == "wetnwild-alphen" })
        park.opening?.exceptions = [
            ParkOpeningException(
                kind: ParkExceptionKind.hours, label: "Extra opening hours", dates: ["2026-09-29"],
                open: "17:00", close: "sunset"
            ),
            ParkOpeningException(
                kind: ParkExceptionKind.hours, label: "Extra opening hours", dates: ["2026-09-30"],
                open: "16:00", close: "sunset"
            ),
            ParkOpeningException(
                kind: ParkExceptionKind.hours, label: "Extra opening hours", dates: ["2026-10-01"],
                open: "17:30", close: "sunset"
            ),
        ]
        return park
    }

    private func clock(_ minute: Int) -> String { ParkSchedule.timeText(minutes: minute) }

    @Test func wetNWildExtraOpeningHoursWeekOpensExtraEvenings() throws {
        let park = try wetNWild()

        // Monday 2026-09-28: not announced, stays closed.
        let monday = park.schedule(on: date("2026-09-28"))
        #expect(monday.isOpen == false)
        #expect(monday.notices.isEmpty)

        // Tuesday 2026-09-29: normally closed, now 17:00 until sunset (00:00, not calculated).
        let tuesday = park.schedule(on: date("2026-09-29"))
        #expect(tuesday.isOpen)
        #expect(tuesday.windows.map(\.startMinute) == [17 * 60])
        #expect(tuesday.windows.map(\.endMinute) == [24 * 60])
        #expect(tuesday.windows.map(\.endsAtSunset) == [true])
        #expect(tuesday.notices.map(\.kind) == [ParkExceptionKind.hours])
        #expect(tuesday.notices.first?.label == "Extra opening hours")
        #expect(tuesday.availableSlots.map(\.start) == ["17:00", "18:00", "19:00"])

        // Wednesday 2026-09-30: 16:00 until sunset replaces the regular 16:00-20:00.
        let wednesday = park.schedule(on: date("2026-09-30"))
        #expect(wednesday.windows.map(\.startMinute) == [16 * 60])
        #expect(wednesday.windows.map(\.endMinute) == [24 * 60])
        #expect(wednesday.availableSlots.map(\.start) == ["16:00", "17:00", "18:00", "19:00"])

        // Thursday 2026-10-01: October, normally closed, now 17:30 until sunset.
        let thursday = park.schedule(on: date("2026-10-01"))
        #expect(thursday.windows.map(\.startMinute) == [17 * 60 + 30])
        #expect(thursday.availableSlots.map(\.start) == ["18:00", "19:00"])

        // Friday closed, weekend 13:00-16:00 (regular October rules).
        #expect(park.schedule(on: date("2026-10-02")).isOpen == false)
        #expect(park.schedule(on: date("2026-10-03")).windows.map(\.startMinute) == [13 * 60])
        #expect(park.schedule(on: date("2026-10-04")).windows.map(\.endMinute) == [16 * 60])

        // The exceptions expire: the next Tuesday is closed again, without notices.
        let nextTuesday = park.schedule(on: date("2026-10-06"))
        #expect(nextTuesday.isOpen == false)
        #expect(nextTuesday.notices.isEmpty)
    }

    @Test func wetNWildExtraOpeningHoursWeekDrivesOpenFilterAndStatus() throws {
        let park = try wetNWild()

        func shown(_ iso: String) -> Bool {
            !ParkListing.filtered([park], favorites: [], filters: ParkFilters(openOnDate: date(iso))).isEmpty
        }
        #expect(shown("2026-09-28") == false)
        #expect(shown("2026-09-29"))
        #expect(shown("2026-09-30"))
        #expect(shown("2026-10-01"))
        #expect(shown("2026-10-02") == false)
        #expect(shown("2026-10-03"))
        #expect(shown("2026-10-06") == false)

        #expect(park.openStatus(at: date("2026-09-28", hour: 12)) == .opensTomorrow)
        #expect(park.openStatus(at: date("2026-09-29", hour: 12)) == .openToday)
        let evening = park.openStatusDetail(at: date("2026-09-29", hour: 18))
        #expect(evening.status == .openToday)
        #expect(evening.windowHasStarted == true)
        // Sunset means closed after 00:00, so still open at 23:00.
        #expect(park.openStatus(at: date("2026-09-29", hour: 23)) == .openToday)
        // Closed after 00:00: Friday is closed, Saturday opens.
        #expect(park.openStatus(at: date("2026-10-02", hour: 1)) == .opensTomorrow)

        let upcoming = park.upcomingExceptions(from: date("2026-09-28"))
        #expect(upcoming.map(\.date) == ["2026-09-29", "2026-09-30", "2026-10-01"])
        #expect(upcoming.allSatisfy { $0.kind == ParkExceptionKind.hours && $0.windows.count == 1 })
        #expect(park.upcomingExceptions(from: date("2026-10-02")).isEmpty)
    }

    private func exceptionPark(_ exceptions: String) throws -> Park {
        try ParkCatalog.parse(yaml: """
        version: 1
        id: exceptions
        name: Exceptions
        location: { lat: 52.136, lon: 4.678 }
        opening:
          rules:
            - { months: [6], days: [wed], open: "16:00", close: "20:00" }
          exceptions:
        \(exceptions)
        """, fallbackId: "x")
    }

    @Test func closedExceptionBeatsRulesAndExtraAndCarriesItsLabel() throws {
        // 2026-06-10 is a Wednesday, normally open 16:00-20:00.
        let park = try exceptionPark("""
            - { kind: extra, dates: ["2026-06-10"], open: "10:00", close: "12:00" }
            - { kind: closed, label: Wind, dates: ["2026-06-10"], note: Too windy }
        """)
        let day = park.schedule(on: date("2026-06-10"))
        #expect(day.isOpen == false)
        #expect(day.isClosedByException)
        #expect(day.notices.compactMap(\.label) == ["Wind"])
        #expect(ParkListing.filtered([park], favorites: [], filters: ParkFilters(openOnDate: date("2026-06-10"))).isEmpty)
        // The next Wednesday is regular again.
        let next = park.schedule(on: date("2026-06-17"))
        #expect(next.isOpen)
        #expect(next.isClosedByException == false)
    }

    @Test func extraExceptionAddsAWindowNextToTheRegularOne() throws {
        let park = try exceptionPark("""
            - { kind: extra, label: Early start, dates: ["2026-06-10"], open: "10:00", close: "12:00" }
        """)
        let day = park.schedule(on: date("2026-06-10"))
        #expect(day.windows.map(\.startMinute) == [10 * 60, 16 * 60])
        // Opens on a normally closed day too.
        let thursday = try exceptionPark("""
            - { kind: extra, dates: ["2026-06-11"], open: "10:00", close: "12:00" }
        """).schedule(on: date("2026-06-11"))
        #expect(thursday.windows.map(\.startMinute) == [10 * 60])
    }

    @Test func eventAndUnknownKindsOnlyAddNotices() throws {
        let park = try exceptionPark("""
            - { kind: event, label: Wake Battle, dates: ["2026-06-10"] }
            - { kind: something-new, label: Future kind, dates: ["2026-06-10"] }
        """)
        let day = park.schedule(on: date("2026-06-10"))
        #expect(day.windows.map(\.startMinute) == [16 * 60])
        #expect(day.notices.map(\.kind) == ["event", "something-new"])
    }

    @Test func exceptionWithoutDateBoundIsIgnored() throws {
        let park = try exceptionPark("""
            - { kind: closed, label: Oops }
        """)
        #expect(park.schedule(on: date("2026-06-10")).isOpen)
        #expect(park.upcomingExceptions(from: date("2026-06-01")).isEmpty)
    }

    @Test func exceptionDateRangeWithDaysSelector() throws {
        // Only Thursday and Friday inside the range; Wednesday keeps its regular hours.
        let park = try exceptionPark("""
            - { kind: hours, from: "2026-06-08", until: "2026-06-14", days: [thu, fri], open: "09:00", close: "10:00" }
        """)
        #expect(park.schedule(on: date("2026-06-10")).windows.map(\.startMinute) == [16 * 60])
        #expect(park.schedule(on: date("2026-06-11")).windows.map(\.startMinute) == [9 * 60])
        #expect(park.schedule(on: date("2026-06-12")).windows.map(\.startMinute) == [9 * 60])
        #expect(park.schedule(on: date("2026-06-18")).isOpen == false)
    }

    @Test func hoursExceptionMakesAnUnknownScheduleKnownForThatDayOnly() throws {
        let park = try ParkCatalog.parse(yaml: """
        version: 1
        id: unknown
        name: Unknown
        location: { lat: 52.0, lon: 4.0 }
        opening:
          note: Only announced days are known
          exceptions:
            - { kind: hours, dates: ["2026-06-10"], open: "09:00", close: "12:00" }
            - { kind: closed, dates: ["2026-06-11"] }
        """, fallbackId: "x")
        let announced = park.schedule(on: date("2026-06-10"))
        #expect(announced.isScheduleKnown)
        #expect(announced.windows.map(\.startMinute) == [9 * 60])
        let closed = park.schedule(on: date("2026-06-11"))
        #expect(closed.isScheduleKnown)
        #expect(closed.isOpen == false)
        #expect(park.schedule(on: date("2026-06-12")).isScheduleKnown == false)
    }

    @Test func sunsetIsTreatedAsMidnight() throws {
        let park = try exceptionPark("""
            - { kind: hours, dates: ["2026-06-10"], open: "23:30", close: sunset }
        """)
        let sunsetDay = park.schedule(on: date("2026-06-10"))
        #expect(sunsetDay.windows.map(\.endMinute) == [24 * 60])
        #expect(sunsetDay.windows.map(\.endsAtSunset) == [true])
        // A plain clock time never counts as sunset (regular Wednesday rule, 16:00-20:00).
        let regular = park.schedule(on: date("2026-06-17"))
        #expect(regular.windows.map(\.endMinute) == [20 * 60])
        #expect(regular.windows.map(\.endsAtSunset) == [false])
    }

    @Test func exceptionsRoundTripThroughYAML() throws {
        let park = try exceptionPark("""
            - { kind: closed, label: Wind, dates: ["2026-06-10"], note: Too windy }
            - { kind: something-new, from: "2026-06-01", until: "2026-06-02" }
        """)
        let decoded = try ParkCatalog.parse(yaml: try ParkCatalog.encode(park), fallbackId: "x")
        #expect(decoded.opening?.exceptions == park.opening?.exceptions)
        #expect(decoded.opening?.exceptions?.last?.kind == "something-new")
    }

    // MARK: - Editing

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func authorAndLegacyDecode() throws {
        let legacy = try ParkCatalog.parse(yaml: "version: 1\nid: a\nname: A\nlocation: { lat: 1, lon: 2 }\n", fallbackId: "a")
        #expect(legacy.author == nil && legacy.basedOnUpdatedAt == nil)
        let park = Park(id: "a", name: "A", location: ParkCoordinate(lat: 1, lon: 2), author: "Duco")
        let decoded = try ParkCatalog.parse(yaml: try ParkCatalog.encode(park), fallbackId: "a")
        #expect(decoded.author == "Duco")
    }

    @Test func emptyIdFallsBackToFilename() throws {
        let yaml = "version: 1\nid: \"\"\nname: A\nlocation: { lat: 1, lon: 2 }\n"
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "from-filename")
        #expect(park.id == "from-filename")
    }

    @Test func loadDirectorySupportsYmlExtension() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let yaml = "version: 1\nid: yml-park\nname: Yml\nlocation: { lat: 1, lon: 2 }\n"
        try yaml.write(to: dir.appendingPathComponent("yml-park.yml"), atomically: true, encoding: .utf8)
        let parks = ParkCatalog.loadDirectory(dir)
        #expect(parks.map(\.id) == ["yml-park"])
    }

    @Test func customParkSaveLoadDelete() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let park = Park(id: "my-park", name: "Mine", location: ParkCoordinate(lat: 52, lon: 4))
        let saved = try ParkCatalog.save(park, to: dir)
        #expect(saved.updatedAt != nil && saved.history?.count == 1)
        let entry = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == "my-park" })
        #expect(entry.origin == .custom)
        try ParkCatalog.deleteUserPark(id: "my-park", userRoot: dir)
        #expect(ParkCatalog.loadWithOrigin(userRoot: dir).allSatisfy { $0.id != "my-park" })
    }

    @Test func resavingAppendsHistoryInsteadOfReplacingIt() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let park = Park(id: "my-park", name: "Mine", location: ParkCoordinate(lat: 52, lon: 4))
        let firstSave = try ParkCatalog.save(park, to: dir)
        #expect(firstSave.history?.count == 1)
        var edited = firstSave
        edited.name = "Mine, renamed"
        let secondSave = try ParkCatalog.save(edited, to: dir)
        #expect(secondSave.history?.count == 2)
        let reloaded = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == "my-park" })
        #expect(reloaded.park.name == "Mine, renamed" && reloaded.park.history?.count == 2)
    }

    @Test func editedOverrideConflictFlow() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = try project7()
        base.updatedAt = "2026-01-01"
        var edit = base
        edit.name = "My Project 7"
        // Override was based on an older bundled version than the one the app ships.
        var stale = try ParkCatalog.save(edit, to: dir, bundledBase: base)
        stale.basedOnUpdatedAt = "2025-01-01"
        try ParkCatalog.encode(stale).write(to: dir.appendingPathComponent("\(stale.id).yaml"), atomically: true, encoding: .utf8)
        let bundledUpdated = try #require(ParkCatalog.loadBundled().first { $0.id == stale.id }?.updatedAt)
        #expect(bundledUpdated > "2025-01-01")
        var entry = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == stale.id })
        #expect(entry.origin == .edited && entry.park.name == "My Project 7" && entry.hasNewerBundled)
        try ParkCatalog.keepMine(entry, userRoot: dir)
        entry = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == stale.id })
        #expect(entry.park.name == "My Project 7" && !entry.hasNewerBundled)
        try ParkCatalog.deleteUserPark(id: stale.id, userRoot: dir)
        entry = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == stale.id })
        #expect(entry.origin == .bundled && entry.park.name != "My Project 7")
    }

    /// A bundled content fix made the same day as the override, with no `updated_at` bump, still
    /// needs to surface as "Update available" — `based_on_revision` (bundled `history.count`)
    /// catches what the day-granularity `updated_at`/`based_on_updated_at` comparison alone would
    /// miss, since both read the same day string.
    @Test func sameDayBundledFixSurfacesViaRevisionNotJustDate() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = try project7()
        // Override was based on the current bundled updated_at (no date lag) but one history
        // entry behind — simulating a same-day bundled fix that only appended to `history`.
        var stale = bundled
        stale.name = "My Project 7"
        stale.basedOnUpdatedAt = bundled.updatedAt
        stale.basedOnRevision = (bundled.history?.count ?? 0) - 1
        try ParkCatalog.encode(stale).write(to: dir.appendingPathComponent("\(stale.id).yaml"), atomically: true, encoding: .utf8)

        let sameDay = (bundled.updatedAt ?? "") > (stale.basedOnUpdatedAt ?? "")
        #expect(!sameDay, "sanity: the date comparison alone can't see a same-day change")

        let entry = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == stale.id })
        #expect(entry.origin == .edited && entry.hasNewerBundled)
    }

    @Test func slugIsAsciiAndUnique() {
        #expect(ParkCatalog.slug(from: "Wet 'n Wild Alphen!") == "wet-n-wild-alphen")
        #expect(ParkCatalog.slug(from: "Café Ünï", existing: ["cafe-uni"]) == "cafe-uni-2")
        #expect(ParkCatalog.slug(from: "***") == "park")
    }

    @Test func draftValidationAndTrace() {
        var park = Park(id: "a", name: " ", location: ParkCoordinate(lat: 0, lon: 0))
        #expect(ParkDraft.validate(park) == [.missingName, .invalidLocation])
        park.name = "A"
        park.location = ParkCoordinate(lat: 52, lon: 4)
        var cable = ParkCable()
        ParkDraft.append(ParkCoordinate(lat: 52, lon: 4), to: &cable)
        park.cables = [cable]
        #expect(ParkDraft.validate(park) == [.cableTooShort(index: 0)])
        ParkDraft.append(ParkCoordinate(lat: 52.001, lon: 4), to: &cable)
        ParkDraft.toggleStart(&cable, index: 1)
        #expect(cable.points?[1].start == true)
        park.cables = [cable]
        #expect(ParkDraft.validate(park).isEmpty)
        ParkDraft.undo(&cable)
        ParkDraft.undo(&cable)
        #expect(cable.points == nil)
    }

    @Test func invalidCablePointIsFlaggedSeparatelyFromTooShort() {
        let cable = ParkCable(points: [ParkCablePoint(lat: 52, lon: 4), ParkCablePoint(lat: 95, lon: 4)])
        var park = Park(id: "a", name: "A", location: ParkCoordinate(lat: 52, lon: 4))
        park.cables = [cable]
        #expect(ParkDraft.validate(park) == [.invalidCablePoint(cable: 0)])
    }

    @Test func centroidOfTracedPointsAcrossCables() throws {
        #expect(ParkDraft.centroid(of: []) == nil)
        #expect(ParkDraft.centroid(of: [ParkCable()]) == nil)
        var cableA = ParkCable()
        ParkDraft.append(ParkCoordinate(lat: 52.0, lon: 4.0), to: &cableA)
        ParkDraft.append(ParkCoordinate(lat: 52.0, lon: 5.0), to: &cableA)
        var cableB = ParkCable()
        ParkDraft.append(ParkCoordinate(lat: 54.0, lon: 4.0), to: &cableB)
        let centroid = try #require(ParkDraft.centroid(of: [cableA, cableB]))
        #expect(abs(centroid.lat - (52.0 + 52.0 + 54.0) / 3) < 1e-9)
        #expect(abs(centroid.lon - (4.0 + 5.0 + 4.0) / 3) < 1e-9)
    }

    @Test func bundledProject7HasWaterTemperatureSource() throws {
        let park = try project7()
        let source = try #require(park.waterTemperature)
        #expect(source.provider == "rws_nl")
        #expect(source.stationId == "krimpenaandeijssel.hollandscheijssel")
    }

    @Test func waterTemperatureSourceRoundTripsThroughYAML() throws {
        var park = Park(id: "x", name: "X", location: ParkCoordinate(lat: 52, lon: 4))
        park.waterTemperature = ParkWaterTemperatureSource(provider: "rws_nl", stationId: "hoekvanholland")
        let yaml = try ParkCatalog.encode(park)
        #expect(yaml.contains("station_id: hoekvanholland"))
        let decoded = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(decoded.waterTemperature == park.waterTemperature)
    }

    @Test func parkWithoutWaterTemperatureSourceDecodesToNil() throws {
        let park = Park(id: "x", name: "X", location: ParkCoordinate(lat: 52, lon: 4))
        let yaml = try ParkCatalog.encode(park)
        let decoded = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(decoded.waterTemperature == nil)
    }

    @Test func staleOverridePredatingWaterTemperatureInheritsBundledSource() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var base = try project7()
        // Simulate an in-app edit (e.g. re-traced cable) saved before `water_temperature` existed
        // on the bundled park.
        base.waterTemperature = nil
        var edit = base
        edit.name = "My Project 7"
        try ParkCatalog.save(edit, to: dir, bundledBase: base)

        let bundledSource = try #require(try project7().waterTemperature)
        let entry = try #require(ParkCatalog.loadWithOrigin(userRoot: dir).first { $0.id == "project7-rotterdam" })
        #expect(entry.origin == .edited && entry.park.name == "My Project 7")
        #expect(entry.park.waterTemperature == bundledSource)

        let loaded = try #require(ParkCatalog.load(userRoot: dir).first { $0.id == "project7-rotterdam" })
        #expect(loaded.waterTemperature == bundledSource)
    }

    @Test func wakesysFlagRoundTripsThroughYAML() throws {
        var park = Park(id: "x", name: "X", location: ParkCoordinate(lat: 52, lon: 4))
        park.wakesys = true
        let yaml = try ParkCatalog.encode(park)
        #expect(yaml.contains("wakesys: true"))
        let decoded = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(decoded.wakesys == true)
    }

    @Test func parkWithoutWakesysFlagDecodesToNil() throws {
        let park = Park(id: "x", name: "X", location: ParkCoordinate(lat: 52, lon: 4))
        let yaml = try ParkCatalog.encode(park)
        let decoded = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(decoded.wakesys == nil)
    }
}

private extension Array where Element == ParkCablePoint {
    var adjacentMeters: Double {
        zip(self, dropFirst()).reduce(0) { $0 + $1.0.coordinate.meters(to: $1.1.coordinate) }
    }
}
