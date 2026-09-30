import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func fix(
    at offset: TimeInterval,
    speedKmh: Double?,
    accuracy: Double? = 5
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

@Suite("LocationFixSequencer")
struct LocationFixSequencerTests {
    @Test func dropsDuplicatesAndOlderFixes() {
        var sequencer = LocationFixSequencer()
        #expect(sequencer.accept(t0))
        #expect(!sequencer.accept(t0))
        #expect(!sequencer.accept(t0.addingTimeInterval(-1)))
        #expect(sequencer.accept(t0.addingTimeInterval(1)))
        #expect(sequencer.droppedCount == 2)
        #expect(sequencer.lastAcceptedAt == t0.addingTimeInterval(1))
    }

    @Test func batchComesBackSortedWithoutRepeats() {
        var sequencer = LocationFixSequencer()
        _ = sequencer.accept(t0.addingTimeInterval(2))
        let batch: [TimeInterval] = [5, 1, 3, 3, 4, 2]
        let accepted = sequencer.accepted(batch.map { t0.addingTimeInterval($0) }) { $0 }
        #expect(accepted == [3, 4, 5].map { t0.addingTimeInterval($0) })
    }

    @Test func resetForgetsHistory() {
        var sequencer = LocationFixSequencer()
        _ = sequencer.accept(t0)
        _ = sequencer.accept(t0)
        sequencer.reset()
        #expect(sequencer.lastAcceptedAt == nil)
        #expect(sequencer.droppedCount == 0)
        #expect(sequencer.accept(t0))
    }
}

/// Field session 2026-09-30: route inserts held good fixes back while poor ones went straight
/// through. The engine timed the set out on the poor fixes, then the held batch arrived a minute
/// late and re-opened a set in the past. Late fixes must not rewind the engine.
@Suite("DetectionStaleFix")
struct DetectionStaleFixTests {
    private func riding() -> DetectionEngine {
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(fix(at: 0, speedKmh: 30))
        _ = engine.process(fix(at: 3.1, speedKmh: 30))
        #expect(engine.currentCode == DetectionCodes.riding)
        return engine
    }

    @Test func fixOlderThanLastFixIsIgnored() {
        var engine = riding()
        let events = engine.process(fix(at: 2, speedKmh: 0))
        #expect(events.isEmpty)
        #expect(engine.lastFilterRejection == "fix_out_of_order")
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    @Test func lateBatchDoesNotReopenTimedOutSet() {
        var engine = riding()
        var offset = 4.0
        var timedOut = false
        while offset <= 80 {
            let events = engine.process(beat(at: offset))
            if events.contains(where: { $0.detectorId == "unsure_timeout" }) { timedOut = true }
            offset += 1
        }
        #expect(timedOut)
        #expect(engine.currentCode == DetectionCodes.inactive)

        // Held-back fixes from the blackout, delivered at once after the timeout.
        for late in stride(from: 10.0, through: 40.0, by: 1.0) {
            #expect(engine.process(fix(at: late, speedKmh: 34)).isEmpty)
        }
        #expect(engine.currentCode == DetectionCodes.inactive)
        #expect(engine.lastFilterRejection?.hasPrefix("fix_stale") == true)
    }

    @Test func slightlyLaggingFixIsStillUsed() {
        var engine = riding()
        _ = engine.process(beat(at: 5))
        _ = engine.process(fix(at: 4.2, speedKmh: 30))
        #expect(engine.lastFilterRejection == nil)
        #expect(engine.currentCode == DetectionCodes.riding)
    }

    @Test func forcedInactiveClearsTheClock() {
        var engine = riding()
        _ = engine.process(beat(at: 100))
        _ = engine.makeForcedInactiveEvent(at: t0, reason: "product_resume", detectorId: "product_resume")
        _ = engine.process(fix(at: 1, speedKmh: 5))
        #expect(engine.lastFilterRejection == nil)
    }
}
