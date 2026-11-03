import Foundation
import Testing
@testable import RpplCore

@Suite("Live iPhone session")
struct LiveSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func firstTapStartsSetOneAndLaterTapsAdvance() {
        var live = LiveSession(startedAt: t0)
        #expect(live.setCount == 0 && live.currentSetStart == nil)
        let first = live.nextSet(at: t0.addingTimeInterval(60))
        let second = live.nextSet(at: t0.addingTimeInterval(400))
        #expect(first && second)
        #expect(live.setCount == 2 && live.currentSetStart == t0.addingTimeInterval(400))
        #expect(live.lastActivityAt == t0.addingTimeInterval(400))
    }

    @Test func doubleTapAndTimeOnlyAreIgnored() {
        var live = LiveSession(startedAt: t0)
        let first = live.nextSet(at: t0.addingTimeInterval(10))
        let double = live.nextSet(at: t0.addingTimeInterval(10.5))
        #expect(first && !double && live.setCount == 1)

        var timeOnly = LiveSession(startedAt: t0, mode: .timeOnly)
        let ignored = timeOnly.nextSet(at: t0.addingTimeInterval(10))
        #expect(!ignored)
        #expect(timeOnly.setCount == 0 && timeOnly.lastActivityAt == t0)
    }

    @Test func stillRunningCheckFollowsLastActivity() {
        var live = LiveSession(startedAt: t0)
        #expect(live.stillRunningCheckAt == t0.addingTimeInterval(7_200))
        live.touch(at: t0.addingTimeInterval(3_600))
        #expect(live.stillRunningCheckAt == t0.addingTimeInterval(10_800))
    }

    @Test func shortSessionWithoutSetsCanBeDiscarded() {
        var live = LiveSession(startedAt: t0)
        #expect(live.isDiscardable(at: t0.addingTimeInterval(29)))
        #expect(!live.isDiscardable(at: t0.addingTimeInterval(31)))
        live.nextSet(at: t0.addingTimeInterval(5))
        #expect(!live.isDiscardable(at: t0.addingTimeInterval(10)))
    }

    @Test func entryKeepsSetsOrLeavesThemUnknown() {
        var live = LiveSession(startedAt: t0, parkId: "p", spot: ParkCoordinate(lat: 1, lon: 2))
        live.nextSet(at: t0.addingTimeInterval(5))
        let entry = live.entry(location: nil)
        #expect(entry.setCount == 1 && entry.setStarts == live.setStarts && entry.location == live.spot)

        let timeOnly = LiveSession(startedAt: t0, mode: .timeOnly).entry(location: ParkCoordinate(lat: 3, lon: 4))
        #expect(timeOnly.setCount == nil && timeOnly.setStarts == nil && timeOnly.location?.lat == 3)
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
