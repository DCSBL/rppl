import Foundation
import Testing
@testable import RpplCore

@Suite("Watch live snapshot")
struct WatchLiveSnapshotTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func snapshot(speed: Double? = 30.2, hr: Double? = 141.4, sets: Int = 3) -> WatchLiveSnapshot {
        WatchLiveSnapshot(
            startedAt: t0, sentAt: t0.addingTimeInterval(60), setCount: sets, setStartedAt: t0.addingTimeInterval(40),
            speedKmh: speed, heartRate: hr, waterCelsius: 17.04, lapCount: 2
        )
    }

    @Test func roundTripsAndStaysSmall() throws {
        let data = try snapshot().encoded()
        #expect(WatchLiveSnapshot.decode(data) == snapshot())
        #expect(data.count < 400)
    }

    @Test func garbageDecodesToNil() {
        #expect(WatchLiveSnapshot.decode(Data("nope".utf8)) == nil)
    }

    @Test func onlyVisibleChangesCount() {
        let base = snapshot()
        var later = base
        later.sentAt = base.sentAt.addingTimeInterval(3)
        later.speedKmh = 30.4
        later.heartRate = 141.0
        #expect(base.showsSame(as: later))
        #expect(!base.showsSame(as: snapshot(speed: 31.2)))
        #expect(!base.showsSame(as: snapshot(sets: 4)))
        #expect(!base.showsSame(as: snapshot(hr: nil)))
    }

    @Test func staleAfterThirtySeconds() {
        let s = snapshot()
        #expect(!s.isStale(at: s.sentAt.addingTimeInterval(30)))
        #expect(s.isStale(at: s.sentAt.addingTimeInterval(31)))
    }
}
