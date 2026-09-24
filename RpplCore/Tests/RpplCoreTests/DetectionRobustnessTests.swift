import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func fix(
    at offset: TimeInterval,
    speedKmh: Double?,
    accuracy: Double? = 10
) -> DetectionTick {
    DetectionTick(
        timestamp: t0.addingTimeInterval(offset),
        speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
        horizontalAccuracy: accuracy
    )
}

private func beat(at offset: TimeInterval) -> DetectionTick {
    .heartbeat(at: t0.addingTimeInterval(offset))
}

/// Enter riding with two usable fast fixes 3.1 s apart.
private func enterRiding(_ engine: inout DetectionEngine) {
    _ = engine.makeSessionStartEvent(at: t0)
    _ = engine.process(fix(at: 0, speedKmh: 22))
    _ = engine.process(fix(at: 3.1, speedKmh: 22))
    #expect(engine.currentCode == DetectionCodes.riding)
}

/// Heartbeats keep the gap and timeout clocks running when GPS goes silent.
/// Before this, ticks only arrived with fixes, so a blackout froze the engine.
@Suite("DetectionHeartbeat")
struct DetectionHeartbeatTests {
    @Test func gpsBlackoutWhileRidingEntersUnsureOnHeartbeatsAlone() {
        var engine = DetectionEngine()
        enterRiding(&engine)

        #expect(engine.process(beat(at: 4)).isEmpty)
        #expect(engine.process(beat(at: 5)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.riding)
        let events = engine.process(beat(at: 7.1))
        #expect(events.first?.code == DetectionCodes.unsure)
        #expect(events.first?.detectorId == "gps_gap")
    }

    @Test func unsureTimesOutWithoutAnyFurtherFix() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = engine.process(beat(at: 4))
        let unsure = engine.process(beat(at: 7.1))
        #expect(unsure.first?.code == DetectionCodes.unsure)

        var timedOut: [DetectionEvent] = []
        var offset = 8.0
        while offset <= 70, timedOut.isEmpty {
            timedOut = engine.process(beat(at: offset))
            offset += 1
        }
        #expect(timedOut.first?.code == DetectionCodes.inactive)
        #expect(timedOut.first?.detectorId == "unsure_timeout")
        #expect(engine.lastConfidentCode == DetectionCodes.inactive)
    }

    @Test func heartbeatsAloneNeverEnterRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        // One dock spike must not become a ride just because heartbeats keep arriving.
        #expect(engine.process(fix(at: 0, speedKmh: 30)).isEmpty)
        for offset in stride(from: 1.0, through: 12.0, by: 1.0) {
            #expect(engine.process(beat(at: offset)).isEmpty)
        }
        #expect(engine.currentCode == DetectionCodes.inactive)
    }

    @Test func shortSilenceKeepsTheEnterHold() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(fix(at: 0, speedKmh: 22))
        #expect(engine.process(beat(at: 1)).isEmpty)
        #expect(engine.process(beat(at: 2)).isEmpty)
        let events = engine.process(fix(at: 3.1, speedKmh: 22))
        #expect(events.first?.code == DetectionCodes.riding)
        #expect(events.first?.timestamp == t0)
    }

    @Test func silenceLongerThanTheGapHoldClearsTheEnterHold() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(fix(at: 0, speedKmh: 22))
        for offset in stride(from: 1.0, through: 8.0, by: 1.0) {
            _ = engine.process(beat(at: offset))
        }
        // Hold restarted at the next fix, so 8 s of silence is not credited as hold time.
        #expect(engine.process(fix(at: 9, speedKmh: 22)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.inactive)
        let events = engine.process(fix(at: 12.1, speedKmh: 22))
        #expect(events.first?.code == DetectionCodes.riding)
        #expect(events.first?.timestamp == t0.addingTimeInterval(9))
    }

    @Test func heartbeatDoesNotOverwriteTheLastFixRejection() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(fix(at: 0, speedKmh: 20, accuracy: 40))
        #expect(engine.lastFilterRejection?.contains("accuracy") == true)
        _ = engine.process(beat(at: 1))
        #expect(engine.lastFilterRejection?.contains("accuracy") == true)
    }

    @Test func replayInjectsHeartbeatsBetweenSparseFixes() {
        let ticks = DetectionEngine.withHeartbeats(
            [fix(at: 0, speedKmh: 22), fix(at: 4, speedKmh: 22)],
            every: 1.0
        )
        #expect(ticks.count == 5)
        #expect(ticks.filter { !$0.hasFreshFix }.count == 3)
        #expect(ticks.map(\.timestamp) == (0...4).map { t0.addingTimeInterval(Double($0)) })
    }

    @Test func replayWithoutHeartbeatsKeepsFixesOnly() {
        let fixes = [fix(at: 0, speedKmh: 22), fix(at: 4, speedKmh: 22)]
        #expect(DetectionEngine.withHeartbeats(fixes, every: nil).count == 2)
    }

    /// A blackout mid-ride must close the set from raw GPS on replay, not only live.
    @Test func replayOverLocationsClosesSetAcrossABlackout() {
        var samples: [LocationSample] = []
        for second in 0...10 {
            samples.append(
                LocationSample(
                    timestamp: t0.addingTimeInterval(Double(second)),
                    latitude: 52,
                    longitude: 5,
                    horizontalAccuracy: 8,
                    speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: 30)
                )
            )
        }
        // 90 s of nothing, then the rider is back at the dock.
        samples.append(
            LocationSample(
                timestamp: t0.addingTimeInterval(100),
                latitude: 52,
                longitude: 5,
                horizontalAccuracy: 8,
                speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: 1)
            )
        )
        let events = DetectionEngine.replay(locations: samples)
        #expect(events.contains { $0.detectorId == "gps_gap" })
        #expect(events.contains { $0.detectorId == "unsure_timeout" })

        let fixOnly = DetectionEngine.replay(locations: samples, heartbeatInterval: nil)
        #expect(!fixOnly.contains { $0.detectorId == "unsure_timeout" })
    }
}

/// The jump filter used to compare every sample against one stale usable speed, and a rejected
/// sample never refreshed it — so a real speed step could reject the rest of a set.
@Suite("GpsSignalFilterJump")
struct GpsSignalFilterJumpTests {
    @Test func sustainedStepIsAcceptedOnItsSecondSample() {
        let filter = GpsSignalFilter()
        let slow = SpeedUnits.metersPerSecond(fromKilometersPerHour: 3)

        let first = filter.evaluate(
            fix(at: 1, speedKmh: 38),
            previousUsableSpeedMps: slow,
            previousUsableAt: t0
        )
        #expect(first.usableSpeedMps == nil)
        #expect(first.rejectionReason?.contains("speed_jump") == true)
        #expect(first.jumpCandidateSpeedMps != nil)

        let second = filter.evaluate(
            fix(at: 2, speedKmh: 38),
            previousUsableSpeedMps: slow,
            previousUsableAt: t0,
            pendingJumpSpeedMps: first.jumpCandidateSpeedMps
        )
        #expect(second.usableSpeedMps != nil)
        #expect(second.rejectionReason == nil)
    }

    @Test func isolatedSpikeIsStillRejected() {
        let filter = GpsSignalFilter()
        let slow = SpeedUnits.metersPerSecond(fromKilometersPerHour: 3)
        let spike = filter.evaluate(
            fix(at: 1, speedKmh: 60),
            previousUsableSpeedMps: slow,
            previousUsableAt: t0
        )
        #expect(spike.usableSpeedMps == nil)
        // Next sample is nowhere near the spike, so nothing corroborates it.
        let after = filter.evaluate(
            fix(at: 2, speedKmh: 4),
            previousUsableSpeedMps: slow,
            previousUsableAt: t0,
            pendingJumpSpeedMps: spike.jumpCandidateSpeedMps
        )
        #expect(after.usableSpeedMps != nil)
    }

    @Test func staleUsableSpeedIsNotComparedAtAll() {
        let filter = GpsSignalFilter()
        let slow = SpeedUnits.metersPerSecond(fromKilometersPerHour: 3)
        let outcome = filter.evaluate(
            fix(at: 36, speedKmh: 38),
            previousUsableSpeedMps: slow,
            previousUsableAt: t0
        )
        #expect(outcome.usableSpeedMps != nil)
        #expect(outcome.rejectionReason == nil)
    }

    @Test func freshUsableSpeedIsStillCompared() {
        let filter = GpsSignalFilter()
        let slow = SpeedUnits.metersPerSecond(fromKilometersPerHour: 3)
        let outcome = filter.evaluate(
            fix(at: 1, speedKmh: 38),
            previousUsableSpeedMps: slow,
            previousUsableAt: t0
        )
        #expect(outcome.usableSpeedMps == nil)
    }

    /// End to end: a hard dock yank straight past the jump limit must still produce a set.
    @Test func hardAccelerationFromTheDockStillEntersRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(fix(at: 0, speedKmh: 2))
        var entered: DetectionEvent?
        for offset in stride(from: 1.0, through: 8.0, by: 1.0) {
            let events = engine.process(fix(at: offset, speedKmh: 38))
            if let event = events.first, event.code == DetectionCodes.riding {
                entered = event
                break
            }
        }
        #expect(entered?.detectorId == "ride_enter")
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    /// The mirror case: a fall drops speed straight past the jump limit and must still end the set.
    @Test func hardDecelerationAfterAFallStillEndsRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(fix(at: 0, speedKmh: 38))
        _ = engine.process(fix(at: 1, speedKmh: 38))
        _ = engine.process(fix(at: 3.1, speedKmh: 38))
        #expect(engine.currentCode == DetectionCodes.riding)
        // A real set, not a failed start, before the fall.
        for offset in stride(from: 4.0, through: 15.0, by: 1.0) {
            _ = engine.process(fix(at: offset, speedKmh: 38))
        }

        var exited: DetectionEvent?
        for offset in stride(from: 16.0, through: 24.0, by: 1.0) {
            let events = engine.process(fix(at: offset, speedKmh: 1))
            if let event = events.first, event.code == DetectionCodes.inactive {
                exited = event
                break
            }
        }
        #expect(exited?.detectorId == "ride_exit")
    }
}
