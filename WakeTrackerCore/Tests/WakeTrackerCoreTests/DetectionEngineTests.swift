import Foundation
import Testing
@testable import WakeTrackerCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tick(
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

@Suite("DetectionEngine")
struct DetectionEngineTests {
    @Test func sessionStartIsPaused() {
        var engine = DetectionEngine()
        let event = engine.makeSessionStartEvent(at: t0)
        #expect(event.code == DetectionCodes.paused)
        #expect(event.reason == "session_start")
        #expect(engine.currentCode == DetectionCodes.paused)
        #expect(engine.lastConfidentCode == DetectionCodes.paused)
    }

    @Test func rideEnterAfterHighSpeedHold() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 16)).isEmpty)
        let events = engine.process(tick(at: 2.1, speedKmh: 16))
        #expect(events.count == 1)
        #expect(events[0].code == DetectionCodes.riding)
        #expect(events[0].detectorId == "ride_enter")
        #expect(engine.currentCode == DetectionCodes.riding)
        #expect(engine.lastConfidentCode == DetectionCodes.riding)
    }

    @Test func midSessionStartCanEnterRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        // Immediately at ride speed (session started mid-ride).
        #expect(engine.process(tick(at: 0, speedKmh: 20)).isEmpty)
        let events = engine.process(tick(at: 2.0, speedKmh: 22))
        #expect(events.first?.code == DetectionCodes.riding)
    }

    @Test func rideExitAfterStoppedHold() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        #expect(engine.currentCode == DetectionCodes.riding)
        #expect(engine.process(tick(at: 3, speedKmh: 2)).isEmpty)
        let events = engine.process(tick(at: 6.1, speedKmh: 1))
        #expect(events.first?.code == DetectionCodes.paused)
        #expect(events.first?.detectorId == "ride_exit")
    }

    @Test func gpsGapEntersUnsureAfterHold() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        #expect(engine.process(tick(at: 3, speedKmh: nil)).isEmpty)
        let events = engine.process(tick(at: 6.1, speedKmh: nil))
        #expect(events.first?.code == DetectionCodes.unsure)
        #expect(engine.lastConfidentCode == DetectionCodes.riding)
        #expect(engine.currentCode == DetectionCodes.unsure)
    }

    @Test func shortGapLookbackKeepsSameRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        _ = engine.process(tick(at: 3, speedKmh: nil))
        let unsure = engine.process(tick(at: 6.1, speedKmh: nil))
        #expect(unsure.first?.code == DetectionCodes.unsure)
        let unsureId = unsure[0].id

        let recovered = engine.process(tick(at: 20, speedKmh: 18, accuracy: 8))
        #expect(recovered.count == 1)
        #expect(recovered[0].code == DetectionCodes.riding)
        #expect(recovered[0].supersedesId == unsureId)
        #expect(recovered[0].detectorId == "lookback")
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    @Test func shortGapLookbackToPauseWhenSlow() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        _ = engine.process(tick(at: 3, speedKmh: nil))
        _ = engine.process(tick(at: 6.1, speedKmh: nil))
        let recovered = engine.process(tick(at: 15, speedKmh: 1, accuracy: 8))
        #expect(recovered.first?.code == DetectionCodes.paused)
        #expect(recovered.first?.supersedesId != nil)
    }

    @Test func longUnsureTimeoutForcesPaused() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        _ = engine.process(tick(at: 3, speedKmh: nil))
        _ = engine.process(tick(at: 6.1, speedKmh: nil))
        #expect(engine.currentCode == DetectionCodes.unsure)

        let timedOut = engine.process(tick(at: 6.1 + 180, speedKmh: nil))
        #expect(timedOut.first?.code == DetectionCodes.paused)
        #expect(timedOut.first?.detectorId == "unsure_timeout")
        #expect(engine.lastConfidentCode == DetectionCodes.paused)
    }

    @Test func longGapThenSpeedIsNewRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        _ = engine.process(tick(at: 3, speedKmh: nil))
        _ = engine.process(tick(at: 6.1, speedKmh: nil))
        _ = engine.process(tick(at: 6.1 + 180, speedKmh: nil))
        #expect(engine.currentCode == DetectionCodes.paused)

        _ = engine.process(tick(at: 200, speedKmh: 18))
        let enter = engine.process(tick(at: 202.1, speedKmh: 18))
        #expect(enter.first?.code == DetectionCodes.riding)
        #expect(enter.first?.detectorId == "ride_enter")
        #expect(enter.first?.supersedesId == nil)
    }

    @Test func badAccuracyDoesNotEnterRide() {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        #expect(engine.process(tick(at: 0, speedKmh: 20, accuracy: 40)).isEmpty)
        #expect(engine.process(tick(at: 3, speedKmh: 20, accuracy: 40)).isEmpty)
        #expect(engine.currentCode == DetectionCodes.paused)
        #expect(engine.lastFilterRejection?.contains("accuracy") == true)
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
        #expect(events.contains { $0.code == DetectionCodes.paused && $0.detectorId == "ride_exit" })
    }
}

@Suite("GpsSignalFilter")
struct GpsSignalFilterTests {
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
}

@Suite("DetectionExtensibility")
struct DetectionExtensibilityTests {
    struct AlwaysPauseDetector: Detector {
        let id = "test_force_pause"
        func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
            guard ctx.currentCode == DetectionCodes.riding else { return nil }
            return DetectionSignal(kind: .exitRide, detectorId: id, reason: "test_force_pause")
        }
    }

    @Test func customDetectorCanPrepend() {
        var engine = DetectionEngine(
            detectors: [AlwaysPauseDetector()] + DetectionEngine.defaultDetectors
        )
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 16))
        _ = engine.process(tick(at: 2.1, speedKmh: 16))
        #expect(engine.currentCode == DetectionCodes.riding)
        let events = engine.process(tick(at: 3, speedKmh: 16))
        #expect(events.first?.detectorId == "test_force_pause")
        #expect(events.first?.code == DetectionCodes.paused)
    }
}
