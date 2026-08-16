import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tick(
    at offset: TimeInterval,
    speedKmh: Double?,
    accuracy: Double? = 10,
    water: String? = nil,
    activity: String? = nil
) -> DetectionTick {
    DetectionTick(
        timestamp: t0.addingTimeInterval(offset),
        speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
        horizontalAccuracy: accuracy,
        waterSubmersionState: water,
        motionActivity: activity
    )
}

/// Enter riding from session start with default thresholds.
private func enterRiding(_ engine: inout DetectionEngine, at start: TimeInterval = 0) {
    _ = engine.makeSessionStartEvent(at: t0)
    _ = engine.process(tick(at: start, speedKmh: 16))
    _ = engine.process(tick(at: start + 2.1, speedKmh: 16))
    #expect(engine.currentCode == DetectionCodes.riding)
}

/// Riding → unsure via sustained unusable GPS.
@discardableResult
private func enterUnsureFromRide(
    _ engine: inout DetectionEngine,
    gapStart: TimeInterval = 3
) -> DetectionEvent {
    _ = engine.process(tick(at: gapStart, speedKmh: nil))
    let events = engine.process(tick(at: gapStart + 3.1, speedKmh: nil))
    #expect(events.first?.code == DetectionCodes.unsure)
    return events[0]
}

@Suite("DetectionEngine")
struct DetectionEngineTests {
    @Test func sessionStartIsInactive() {
        var engine = DetectionEngine()
        let event = engine.makeSessionStartEvent(at: t0)
        #expect(event.code == DetectionCodes.inactive)
        #expect(event.reason == "session_start")
        #expect(event.detectorId == "session_start")
        #expect(engine.currentCode == DetectionCodes.inactive)
        #expect(engine.lastConfidentCode == DetectionCodes.inactive)
    }

    @Test func processReturnsEmptyWhenCodeUnchanged() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 5)).isEmpty)
        #expect(engine.process(tick(at: 1, speedKmh: 5)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.inactive)
    }

    @Test func rideEnterAfterHighSpeedHold() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 16)).isEmpty)
        let events = engine.process(tick(at: 2.1, speedKmh: 16))
        #expect(events.count == 1)
        #expect(events[0].code == DetectionCodes.riding)
        #expect(events[0].detectorId == "ride_enter")
        #expect(events[0].reason.contains("ride_enter"))
        #expect(engine.currentCode == DetectionCodes.riding)
        #expect(engine.lastConfidentCode == DetectionCodes.riding)
    }

    @Test func rideEnterRequiresHoldDuration() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 20)).isEmpty)
        // 1.5 s < default 2.0 s hold
        #expect(engine.process(tick(at: 1.5, speedKmh: 20)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.inactive)
        let events = engine.process(tick(at: 2.0, speedKmh: 20))
        #expect(events.first?.code == DetectionCodes.riding)
    }

    @Test func midSessionStartCanEnterRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 20)).isEmpty)
        let events = engine.process(tick(at: 2.0, speedKmh: 22))
        #expect(events.first?.code == DetectionCodes.riding)
    }

    @Test func walkBandSpeedDoesNotEnterRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 8)).isEmpty)
        #expect(engine.process(tick(at: 5, speedKmh: 8)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.inactive)
    }

    @Test func waterSubmergedEndsRideActivityStillIgnored() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        // Dock: submerged + walking must not invent swim/walk codes.
        #expect(
            engine.process(
                tick(at: 0, speedKmh: 3, water: "submerged", activity: "walking")
            ).isEmpty
        )
        #expect(engine.currentCode == DetectionCodes.inactive)

        enterRiding(&engine)
        #expect(engine.currentCode == DetectionCodes.riding)

        let exited = engine.process(
            tick(at: 5, speedKmh: 18, water: "submerged", activity: "walking")
        )
        #expect(exited.first?.code == DetectionCodes.inactive)
        #expect(exited.first?.detectorId == "water_exit")
        #expect(exited.first?.waterSubmersionState == "submerged")
        #expect(exited.first?.motionActivity == "walking")
        #expect(engine.lastConfidentCode == DetectionCodes.inactive)

        // Later start is a new ride (no long water same-ride glue).
        _ = engine.process(tick(at: 120, speedKmh: 18, water: "notSubmerged"))
        let enter = engine.process(tick(at: 122.1, speedKmh: 18, water: "notSubmerged"))
        #expect(enter.first?.code == DetectionCodes.riding)
        #expect(enter.first?.detectorId == "ride_enter")
        #expect(enter.first?.supersedesId == nil)
    }

    @Test func waterExitFromUnsure() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine)
        let exited = engine.process(tick(at: 10, speedKmh: nil, water: "submerged"))
        #expect(exited.first?.code == DetectionCodes.inactive)
        #expect(exited.first?.detectorId == "water_exit")
    }

    @Test func rideExitAfterStoppedHold() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        #expect(engine.process(tick(at: 3, speedKmh: 2)).isEmpty)
        let events = engine.process(tick(at: 6.1, speedKmh: 1))
        #expect(events.first?.code == DetectionCodes.inactive)
        #expect(events.first?.detectorId == "ride_exit")
    }

    @Test func rideExitRequiresUsableSlowSpeed() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        // Unusable GPS while riding goes to unsure path, not ride_exit.
        #expect(engine.process(tick(at: 3, speedKmh: nil)).isEmpty)
        let events = engine.process(tick(at: 6.1, speedKmh: nil))
        #expect(events.first?.code == DetectionCodes.unsure)
        #expect(events.first?.detectorId == "gps_gap")
    }

    @Test func gpsGapIgnoresSingleBadTick() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        #expect(engine.process(tick(at: 3, speedKmh: nil)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.riding)
        // Usable again before gap hold → stay riding
        #expect(engine.process(tick(at: 4, speedKmh: 18)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    @Test func gpsGapEntersUnsureAfterHold() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        let unsure = enterUnsureFromRide(&engine)
        #expect(unsure.detectorId == "gps_gap")
        #expect(engine.lastConfidentCode == DetectionCodes.riding)
        #expect(engine.currentCode == DetectionCodes.unsure)
    }

    @Test func shortGapLookbackKeepsSameRide() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        let unsure = enterUnsureFromRide(&engine)
        let unsureId = unsure.id

        let recovered = engine.process(tick(at: 20, speedKmh: 18, accuracy: 8))
        #expect(recovered.count == 1)
        #expect(recovered[0].code == DetectionCodes.riding)
        #expect(recovered[0].supersedesId == unsureId)
        #expect(recovered[0].detectorId == "lookback")
        #expect(recovered[0].reason.contains("lookback_same_ride"))
        #expect(engine.currentCode == DetectionCodes.riding)
        #expect(engine.lastConfidentCode == DetectionCodes.riding)
    }

    @Test func shortGapLookbackToInactiveWhenSlow() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine)
        let recovered = engine.process(tick(at: 15, speedKmh: 1, accuracy: 8))
        #expect(recovered.first?.code == DetectionCodes.inactive)
        #expect(recovered.first?.detectorId == "lookback")
        #expect(recovered.first?.supersedesId != nil)
        #expect(recovered.first?.reason.contains("lookback_inactive") == true)
        #expect(engine.lastConfidentCode == DetectionCodes.inactive)
    }

    @Test func midBandUsableSpeedWhileUnsureStaysUnsure() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine)
        // 8 km/h is above stop and below ride-enter — no lookback yet
        #expect(engine.process(tick(at: 20, speedKmh: 8, accuracy: 8)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.unsure)
        #expect(engine.lastConfidentCode == DetectionCodes.riding)
    }

    @Test func lookbackSameRideJustUnderSixtySeconds() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        let unsure = enterUnsureFromRide(&engine) // unsure at t=6.1
        // Age 59 s < 60 s window
        let recovered = engine.process(tick(at: 6.1 + 59, speedKmh: 18, accuracy: 8))
        #expect(recovered.first?.code == DetectionCodes.riding)
        #expect(recovered.first?.supersedesId == unsure.id)
        #expect(recovered.first?.detectorId == "lookback")
    }

    @Test func recoverAfterSixtySecondsIsNewRideNotLookback() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine) // unsure at 6.1
        // At exactly 60 s: timeout to inactive first
        let timedOut = engine.process(tick(at: 6.1 + 60, speedKmh: nil))
        #expect(timedOut.first?.code == DetectionCodes.inactive)
        #expect(timedOut.first?.detectorId == "unsure_timeout")

        _ = engine.process(tick(at: 80, speedKmh: 18))
        let enter = engine.process(tick(at: 82.1, speedKmh: 18))
        #expect(enter.first?.code == DetectionCodes.riding)
        #expect(enter.first?.detectorId == "ride_enter")
        #expect(enter.first?.supersedesId == nil)
    }

    @Test func longUnsureTimeoutForcesInactive() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine)
        #expect(engine.currentCode == DetectionCodes.unsure)

        let timedOut = engine.process(tick(at: 6.1 + 60, speedKmh: nil))
        #expect(timedOut.first?.code == DetectionCodes.inactive)
        #expect(timedOut.first?.detectorId == "unsure_timeout")
        #expect(engine.lastConfidentCode == DetectionCodes.inactive)
    }

    @Test func longGapThenSpeedIsNewRide() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine)
        _ = engine.process(tick(at: 6.1 + 60, speedKmh: nil))
        #expect(engine.currentCode == DetectionCodes.inactive)

        _ = engine.process(tick(at: 80, speedKmh: 18))
        let enter = engine.process(tick(at: 82.1, speedKmh: 18))
        #expect(enter.first?.code == DetectionCodes.riding)
        #expect(enter.first?.detectorId == "ride_enter")
        #expect(enter.first?.supersedesId == nil)
    }

    @Test func badAccuracyDoesNotEnterRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 20, accuracy: 40)).isEmpty)
        #expect(engine.process(tick(at: 3, speedKmh: 20, accuracy: 40)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.inactive)
        #expect(engine.lastFilterRejection?.contains("accuracy") == true)
    }

    @Test func fullParkLoopRideUnsureInactiveRide() {
        var engine = DetectionEngine()
        enterRiding(&engine)
        _ = enterUnsureFromRide(&engine)
        let pause = engine.process(tick(at: 20, speedKmh: 1, accuracy: 8))
        #expect(pause.first?.code == DetectionCodes.inactive)

        _ = engine.process(tick(at: 30, speedKmh: 17))
        let ride2 = engine.process(tick(at: 32.1, speedKmh: 17))
        #expect(ride2.first?.code == DetectionCodes.riding)
        #expect(ride2.first?.detectorId == "ride_enter")
    }

    @Test func replayMatchesLivePipeline() {
        let ticks = [
            tick(at: 0, speedKmh: 16),
            tick(at: 2.1, speedKmh: 16),
            tick(at: 5, speedKmh: 2),
            tick(at: 8.1, speedKmh: 1),
        ]
        let events = DetectionEngine.replay(ticks: ticks)
        #expect(events.first?.reason == "session_start")
        #expect(events.contains { $0.code == DetectionCodes.riding && $0.detectorId == "ride_enter" })
        #expect(events.contains { $0.code == DetectionCodes.inactive && $0.detectorId == "ride_exit" })
        #expect(events.filter { $0.code == DetectionCodes.riding }.count == 1)
    }

    @Test func replayFromLocationSamples() {
        let locations = [
            LocationSample(
                timestamp: t0,
                latitude: 52,
                longitude: 5,
                horizontalAccuracy: 10,
                speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: 16)
            ),
            LocationSample(
                timestamp: t0.addingTimeInterval(2.1),
                latitude: 52.001,
                longitude: 5.001,
                horizontalAccuracy: 10,
                speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: 16)
            ),
        ]
        let events = DetectionEngine.replay(locations: locations)
        #expect(events.first?.code == DetectionCodes.inactive)
        #expect(events.contains { $0.code == DetectionCodes.riding })
    }

    @Test func replayEmptyTicksStillEmitsSessionStart() {
        let events = DetectionEngine.replay(ticks: [])
        #expect(events.count == 1)
        #expect(events[0].reason == "session_start")
    }
}

@Suite("GpsSignalFilter")
struct GpsSignalFilterTests {
    @Test func rejectsNilSpeed() {
        let filter = GpsSignalFilter()
        let outcome = filter.evaluate(tick(at: 0, speedKmh: nil), previousUsableSpeedMps: nil)
        #expect(outcome.usableSpeedMps == nil)
        #expect(outcome.rejectionReason == "nil_speed")
    }

    @Test func rejectsBadAccuracy() {
        let filter = GpsSignalFilter()
        let outcome = filter.evaluate(
            tick(at: 0, speedKmh: 10, accuracy: 40),
            previousUsableSpeedMps: nil
        )
        #expect(outcome.usableSpeedMps == nil)
        #expect(outcome.rejectionReason?.contains("accuracy") == true)
    }

    @Test func rejectsNegativeAccuracy() {
        let filter = GpsSignalFilter()
        let outcome = filter.evaluate(
            tick(at: 0, speedKmh: 10, accuracy: -1),
            previousUsableSpeedMps: nil
        )
        #expect(outcome.usableSpeedMps == nil)
        #expect(outcome.rejectionReason == "accuracy_negative")
    }

    @Test func rejectsImplausibleSpeed() {
        let filter = GpsSignalFilter()
        let outcome = filter.evaluate(
            tick(at: 0, speedKmh: 50),
            previousUsableSpeedMps: nil
        )
        #expect(outcome.usableSpeedMps == nil)
        #expect(outcome.rejectionReason?.contains("implausible") == true)
    }

    @Test func rejectsSpeedJump() {
        let filter = GpsSignalFilter()
        let first = filter.evaluate(
            tick(at: 0, speedKmh: 10),
            previousUsableSpeedMps: nil
        )
        #expect(first.usableSpeedMps != nil)
        let jumped = filter.evaluate(
            tick(at: 1, speedKmh: 45),
            previousUsableSpeedMps: first.usableSpeedMps
        )
        #expect(jumped.usableSpeedMps == nil)
        #expect(jumped.rejectionReason?.contains("speed_jump") == true)
    }

    @Test func acceptsStableUsableSpeed() {
        let filter = GpsSignalFilter()
        let first = filter.evaluate(tick(at: 0, speedKmh: 12), previousUsableSpeedMps: nil)
        let second = filter.evaluate(
            tick(at: 1, speedKmh: 14),
            previousUsableSpeedMps: first.usableSpeedMps
        )
        #expect(second.usableSpeedMps != nil)
        #expect(second.rejectionReason == nil)
    }
}

@Suite("DetectionEventCodable")
struct DetectionEventCodableTests {
    @Test func roundTripPreservesSupersedesAndDetector() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = DetectionEvent(
            id: "evt-1",
            code: DetectionCodes.riding,
            timestamp: t0,
            reason: "lookback_same_ride",
            detectorId: "lookback",
            speedMps: 5,
            horizontalAccuracy: 8,
            waterSubmersionState: "notSubmerged",
            motionActivity: "unknown",
            supersedesId: "evt-0"
        )
        let decoded = try decoder.decode(
            DetectionEvent.self,
            from: try encoder.encode(original)
        )
        #expect(decoded == original)
    }

    @Test func decodesLegacyLineWithoutDetectorId() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = Data(
            #"{"code":"riding","id":"a1","reason":"ride_start","timestamp":"2024-01-01T00:00:00Z"}"#
                .utf8
        )
        let event = try decoder.decode(DetectionEvent.self, from: json)
        #expect(event.code == "riding")
        #expect(event.id == "a1")
        #expect(event.detectorId == "unknown")
    }
}

@Suite("DetectionExtensibility")
struct DetectionExtensibilityTests {
    struct AlwaysInactiveDetector: Detector {
        let id = "test_force_inactive"
        func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
            guard ctx.currentCode == DetectionCodes.riding else { return nil }
            return DetectionSignal(kind: .exitRide, detectorId: id, reason: "test_force_inactive")
        }
    }

    @Test func customDetectorCanPrepend() {
        var engine = DetectionEngine(
            detectors: [AlwaysInactiveDetector()] + DetectionEngine.defaultDetectors
        )
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        #expect(engine.currentCode == DetectionCodes.riding)
        let events = engine.process(tick(at: 3, speedKmh: 16))
        #expect(events.first?.detectorId == "test_force_inactive")
        #expect(events.first?.code == DetectionCodes.inactive)
    }
}
