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
        #expect(Park(id: "x", name: "X", location: ParkCoordinate(lat: 0, lon: 0)).openStatus() == .closed)
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
        let updated = try #require(try project7().lastUpdated)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        let parts = calendar.dateComponents([.year, .month, .day], from: updated)
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 24)
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
        #expect(park.prices?.count == 8)
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

    @Test func hoursUnknownOverridesRulesAndSlots() throws {
        let yaml = """
        version: 1
        id: unknown-hours
        name: Unknown
        location: { lat: 52.0, lon: 4.0 }
        opening:
          hours_unknown: true
          slots:
            - { id: a, start: "10:00", end: "11:00" }
          rules:
            - { days: [mon], open: "10:00", close: "11:00" }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        let day = park.schedule(on: date("2026-09-24"))
        #expect(day.isScheduleKnown == false)
        #expect(day.isOpen == false)
        #expect(day.availableSlots.isEmpty)
        #expect(park.openStatus(at: date("2026-09-24", hour: 10)) == .unknown)
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
          - { name: Beginner, direction: 2d, length_m: 320, description: Short }
          - { direction: custom-loop }
        """
        let park = try ParkCatalog.parse(yaml: yaml, fallbackId: "x")
        #expect(park.opening == nil)
        #expect(park.cables?.first?.effectiveLengthM == 320)
        #expect(park.cables?.first?.direction == .twoD)
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
        #expect(abs(open - 666.3) < 1)
        #expect(abs(length - 763.5) < 1)
        var twoD = cable
        twoD.direction = .twoD
        #expect(twoD.computedLengthM == open)
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
        let byDistance = ParkListing.sorted(parks, favorites: ["fav"], visits: [:], userLocation: me, sort: .distance)
        #expect(byDistance.map(\.id) == ["fav", "near", "far"])
        let byVisits = ParkListing.sorted(parks, favorites: [], visits: ["far": 3, "near": 1], userLocation: me, sort: .visits)
        #expect(byVisits.map(\.id) == ["far", "near", "fav"])
        let noFix = ParkListing.sorted(parks, favorites: [], visits: [:], userLocation: nil, sort: .distance)
        #expect(noFix.map(\.id) == ["far", "near", "fav"])

        let counts = ParkListing.visitCounts(
            parks: parks,
            sessionCenters: [me, ParkCoordinate(lat: 52.002, lon: 4.0), ParkCoordinate(lat: 10, lon: 10)]
        )
        #expect(counts == ["near": 2])
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
        let twoDOnly = ParkFilters(cableDirections: [.twoD])
        #expect(ParkListing.filtered(parks, favorites: [], filters: twoDOnly).isEmpty)

        // 2026-09-24 (Thursday) project7 is open; 2026-10-07 both are closed.
        let openThursday = ParkFilters(openOnDate: date("2026-09-24"))
        #expect(ParkListing.filtered(parks, favorites: [], filters: openThursday).map(\.id).contains(project7.id))
        let closedDay = ParkFilters(openOnDate: date("2026-10-07"))
        #expect(ParkListing.filtered(parks, favorites: [], filters: closedDay).isEmpty)

        // Cleared filters show everything, including closed parks.
        #expect(ParkListing.filtered(parks, favorites: [], filters: ParkFilters()).map(\.id) == parks.map(\.id))
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
}

private extension Array where Element == ParkCablePoint {
    var adjacentMeters: Double {
        zip(self, dropFirst()).reduce(0) { $0 + $1.0.coordinate.meters(to: $1.1.coordinate) }
    }
}
