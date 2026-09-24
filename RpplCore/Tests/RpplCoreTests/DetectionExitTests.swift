import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func fix(at offset: TimeInterval, speedKmh: Double?) -> DetectionTick {
    DetectionTick(
        timestamp: t0.addingTimeInterval(offset),
        speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
        horizontalAccuracy: 10
    )
}

/// Drive the engine over a speed profile given as `(secondsOffset, km/h)` and collect every event.
private func run(
    _ profile: [(TimeInterval, Double?)],
    thresholds: DetectionThresholds = .default
) -> (events: [DetectionEvent], engine: DetectionEngine) {
    var engine = DetectionEngine(thresholds: thresholds)
    var events = [engine.makeSessionStartEvent(at: t0)]
    for (offset, speed) in profile {
        events.append(contentsOf: engine.process(fix(at: offset, speedKmh: speed)))
    }
    return (events, engine)
}

/// One second per entry, from `start` through `end` inclusive.
private func seconds(_ range: ClosedRange<Int>, _ speedKmh: Double?) -> [(TimeInterval, Double?)] {
    range.map { (TimeInterval($0), speedKmh) }
}

private func manifest(endedAt: Date) -> SessionManifest {
    SessionManifest(
        sessionId: "exit-session",
        testerId: "tester",
        appVersion: "1.0",
        buildNumber: "1",
        watchModel: "Watch",
        systemVersion: "26.0",
        startedAt: t0,
        endedAt: endedAt,
        transferState: .acknowledged
    )
}

/// Letting go of the cable leaves the rider swimming or coasting in the 4–8 km/h band for tens of
/// seconds. The <=4 km/h exit only fires at the end of that decay, so sets ran systematically long.
@Suite("RideExitOffCable")
struct RideExitOffCableTests {
    @Test func exitIsBackdatedToWhereTheRiderLeftTheCable() {
        let (events, engine) = run(seconds(0...19, 31) + seconds(20...30, 7))
        let exit = events.last
        #expect(exit?.detectorId == "ride_exit_offcable")
        #expect(exit?.code == DetectionCodes.inactive)
        // Dropped below 13 km/h at t=20; hold satisfied at t=24; event carries t=20.
        #expect(exit?.timestamp == t0.addingTimeInterval(20))
        #expect(engine.currentCode == DetectionCodes.inactive)
    }

    @Test func cableSpeedNeverExits() {
        let (events, engine) = run(seconds(0...3, 31) + seconds(4...30, 22))
        #expect(events.filter { $0.code == DetectionCodes.inactive && $0.detectorId != "session_start" }.isEmpty)
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    /// A corner or a moment of slack must not split one set in two.
    @Test func briefDipBelowTheBandDoesNotExit() {
        let profile = seconds(0...3, 31) + seconds(4...6, 10) + seconds(7...20, 31)
        let (events, engine) = run(profile)
        #expect(events.filter { $0.detectorId == "ride_exit_offcable" }.isEmpty)
        #expect(events.filter { $0.detectorId == "ride_enter" }.count == 1)
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    /// The <=4 km/h rule stays the fast path: it is one second quicker than the wider band.
    @Test func stoppedExitStillWinsWhenTheRiderStops() {
        let (events, _) = run(seconds(0...9, 25) + seconds(10...20, 1))
        let exit = events.first { $0.code == DetectionCodes.inactive && $0.detectorId.hasPrefix("ride_exit") }
        #expect(exit?.detectorId == "ride_exit")
        #expect(exit?.timestamp == t0.addingTimeInterval(13))
    }

    @Test func offCableBandSitsBetweenWalkingAndTheCable() {
        let thresholds = DetectionThresholds.default
        #expect(thresholds.offCableSpeedKmh > thresholds.walkBandSpeedKmh)
        #expect(thresholds.offCableSpeedKmh < thresholds.rideEnterSpeedKmh)
        #expect(thresholds.offCableExitHold > thresholds.rideExitHold)
    }
}

/// A set that never became one — a dock GPS spike, or a yank that ended immediately — is taken
/// back by superseding its own `ride_enter`, so it never reaches stats. No new detection code.
@Suite("FailedStart")
struct FailedStartTests {
    /// Enter on the minimum hold, stop straight away: 3 s of cable evidence in a 7 s set.
    private static let dockSpike = seconds(0...3, 25) + seconds(4...10, 1)

    @Test func dockSpikeRevokesItsOwnEnter() {
        let (events, _) = run(Self.dockSpike)
        let enter = events.first { $0.detectorId == "ride_enter" }
        let revocation = events.last

        #expect(enter != nil)
        #expect(revocation?.detectorId == "failed_start")
        #expect(revocation?.code == DetectionCodes.inactive)
        #expect(revocation?.supersedesId == enter?.id)
        #expect(revocation?.timestamp == enter?.timestamp)
        #expect(revocation?.reason.contains("via=ride_exit") == true)
    }

    @Test func revokedSetNeverReachesDerivedStats() {
        let (events, _) = run(Self.dockSpike)
        let stats = SessionStatsBuilder.build(
            manifest: manifest(endedAt: t0.addingTimeInterval(60)),
            detections: events,
            locations: [],
            health: []
        )
        #expect(stats.setCount == 0)
        #expect(stats.ridingDuration == 0)
    }

    @Test func liveTrackerTakesTheSetBackToo() {
        var engine = DetectionEngine()
        var tracker = LiveSetTracker()
        _ = engine.makeSessionStartEvent(at: t0)
        var sawSet = false
        for (offset, speed) in Self.dockSpike {
            let events = engine.process(fix(at: offset, speedKmh: speed))
            tracker.update(
                currentCode: engine.currentCode,
                lastConfident: engine.lastConfidentCode,
                events: events
            )
            sawSet = sawSet || tracker.setCount == 1
        }
        #expect(sawSet, "the spike must open a set before it is taken back")
        #expect(tracker.setCount == 0)
        #expect(!tracker.isSetOngoing)
        #expect(tracker.sessionRidingDuration == 0)
    }

    /// Young enough to be a candidate, but it showed 7 s of cable speed where the spike showed 3.
    @Test func shortRealRideIsKeptOnEvidence() {
        let (events, _) = run(seconds(0...7, 25) + seconds(8...15, 1))
        #expect(events.filter { $0.detectorId == "failed_start" }.isEmpty)
        let exit = events.first { $0.detectorId == "ride_exit" }
        #expect(exit?.timestamp == t0.addingTimeInterval(11))
        #expect(exit?.supersedesId == nil)
    }

    @Test func fullSetIsNeverRevoked() {
        let (events, _) = run(seconds(0...120, 31) + seconds(121...130, 1))
        #expect(events.filter { $0.detectorId == "failed_start" }.isEmpty)
        #expect(events.filter { $0.detectorId == "ride_enter" }.count == 1)
    }

    /// Weak cable evidence (a long stretch just under the enter speed) but far too old to revoke:
    /// revocation is only for sets that are both young and unproven.
    @Test func ageAloneKeepsAnUnprovenSet() {
        let profile = seconds(0...3, 25) + seconds(4...20, 15) + seconds(21...30, 1)
        let (events, _) = run(profile)
        #expect(events.filter { $0.detectorId == "failed_start" }.isEmpty)
        #expect(events.first { $0.detectorId == "ride_exit" }?.timestamp == t0.addingTimeInterval(24))
    }

    @Test func revocationSurvivesReplayOverRawLocations() {
        let samples = Self.dockSpike.map { offset, speedKmh in
            LocationSample(
                timestamp: t0.addingTimeInterval(offset),
                latitude: 52,
                longitude: 5,
                horizontalAccuracy: 8,
                speed: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) }
            )
        }
        let events = DetectionEngine.replay(locations: samples)
        #expect(events.contains { $0.detectorId == "failed_start" })
    }
}
