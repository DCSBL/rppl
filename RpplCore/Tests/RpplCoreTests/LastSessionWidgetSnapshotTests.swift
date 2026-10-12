import Foundation
import Testing
@testable import RpplCore

struct LastSessionWidgetSnapshotTests {
    private func snapshot(_ id: String = "s1", sets: Int? = 3) -> LastSessionWidgetSnapshot {
        LastSessionWidgetSnapshot(
            sessionId: id, place: "Hoorn", startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 3600), duration: 3600, ridingRatio: 0.4,
            setCount: sets, lapCount: nil, setSpans: [0.1...0.2, 0.5...0.9]
        )
    }

    @Test func storeRoundTripsAndReportsChange() throws {
        let suite = "LastSessionWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LastSessionWidgetStore.load(from: defaults) == nil)
        #expect(LastSessionWidgetStore.save(snapshot(), in: defaults))
        #expect(!LastSessionWidgetStore.save(snapshot(), in: defaults))
        #expect(LastSessionWidgetStore.load(from: defaults) == snapshot())
        #expect(LastSessionWidgetStore.save(snapshot(sets: 4), in: defaults))
    }

    @Test func decodesSnapshotWithoutRidingDurations() throws {
        let old = """
        {"sessionId":"s1","startedAt":0,"endedAt":3600,"duration":3600,"ridingRatio":0.4,"setSpans":[]}
        """
        let decoded = try JSONDecoder().decode(LastSessionWidgetSnapshot.self, from: Data(old.utf8))
        #expect(decoded.ridingDuration == nil)
        #expect(decoded.inactiveDuration == nil)
    }

    @Test func deepLinkRoundTripsSessionID() throws {
        let url = try #require(SessionDeepLink.url(forSessionID: "abc-123"))
        #expect(SessionDeepLink.sessionID(from: url) == "abc-123")
        #expect(SessionDeepLink.sessionID(from: try #require(ParkDeepLink.url(forParkID: "abc"))) == nil)
        #expect(ParkDeepLink.parkID(from: url) == nil)
    }
}
