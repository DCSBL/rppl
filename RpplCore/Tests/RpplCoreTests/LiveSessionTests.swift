import Foundation
import Testing
@testable import RpplCore

@Suite("Live iPhone session")
struct LiveSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func setOneStartsWithTheSessionAndTapsAdvance() {
        var live = LiveSession(startedAt: t0)
        #expect(live.setCount == 1 && live.currentSetStart == t0 && live.setStarts == [t0])
        let second = live.nextSet(at: t0.addingTimeInterval(400))
        let third = live.nextSet(at: t0.addingTimeInterval(900))
        #expect(second && third)
        #expect(live.setCount == 3 && live.currentSetStart == t0.addingTimeInterval(900))
        #expect(live.lastActivityAt == t0.addingTimeInterval(900))
    }

    @Test func doubleTapIsIgnored() {
        var live = LiveSession(startedAt: t0)
        let first = live.nextSet(at: t0.addingTimeInterval(10))
        let double = live.nextSet(at: t0.addingTimeInterval(10.5))
        #expect(first && !double && live.setCount == 2)
    }

    @Test func stillRunningCheckFollowsLastActivity() {
        var live = LiveSession(startedAt: t0)
        #expect(live.stillRunningCheckAt == t0.addingTimeInterval(7_200))
        live.touch(at: t0.addingTimeInterval(3_600))
        #expect(live.stillRunningCheckAt == t0.addingTimeInterval(10_800))
    }

    @Test func shortSessionWithoutSecondSetCanBeDiscarded() {
        var live = LiveSession(startedAt: t0)
        #expect(live.isDiscardable(at: t0.addingTimeInterval(29)))
        #expect(!live.isDiscardable(at: t0.addingTimeInterval(31)))
        live.nextSet(at: t0.addingTimeInterval(5))
        #expect(!live.isDiscardable(at: t0.addingTimeInterval(10)))
    }

    @Test func entryIsDurationOnlyUntilASecondSet() {
        var live = LiveSession(startedAt: t0, parkId: "p", spot: ParkCoordinate(lat: 1, lon: 2))
        let single = live.entry(location: nil)
        #expect(single.setCount == nil && single.setStarts == nil && single.location == live.spot)

        live.nextSet(at: t0.addingTimeInterval(500))
        let entry = live.entry(location: ParkCoordinate(lat: 3, lon: 4))
        #expect(entry.setCount == 2 && entry.setStarts == [t0, t0.addingTimeInterval(500)] && entry.location?.lat == 3)
    }

    @Test func fileRoundTripsAndRemoves() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-\(UUID().uuidString)/live-session.json")
        let file = LiveSessionFile(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(file.load() == nil)

        var live = LiveSession(startedAt: t0, parkId: "p7")
        live.nextSet(at: t0.addingTimeInterval(90))
        try file.save(live)
        #expect(file.load() == live)

        file.remove()
        #expect(file.load() == nil)
    }
}
