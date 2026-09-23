import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func manifest(endedAt: Date) -> SessionManifest {
    SessionManifest(
        sessionId: "agreement-session",
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

private func event(
    _ code: String,
    at offset: TimeInterval,
    id: String,
    supersedesId: String? = nil
) -> DetectionEvent {
    DetectionEvent(
        id: id,
        code: code,
        timestamp: t0.addingTimeInterval(offset),
        reason: code,
        detectorId: "test",
        supersedesId: supersedesId
    )
}

/// Feed one event stream through the live tracker exactly as the Watch does (one `update` per
/// engine tick) and return the finished-set durations it reports.
private func liveSetDurations(_ events: [DetectionEvent], stopAt: TimeInterval) -> (count: Int, riding: TimeInterval) {
    var tracker = LiveSetTracker()
    var code = DetectionCodes.inactive
    var lastConfident = DetectionCodes.inactive
    for event in events {
        code = DetectionCodes.normalize(event.code)
        if DetectionCodes.isConfident(event.code) {
            lastConfident = code
        }
        tracker.update(currentCode: code, lastConfident: lastConfident, events: [event])
    }
    tracker.closeOpenSet(at: t0.addingTimeInterval(stopAt))
    return (tracker.setCount, tracker.sessionRidingDuration)
}

private func derivedSets(_ events: [DetectionEvent], stopAt: TimeInterval) -> SessionStats {
    SessionStatsBuilder.build(
        manifest: manifest(endedAt: t0.addingTimeInterval(stopAt)),
        detections: events,
        locations: [],
        health: []
    )
}

/// The Watch stop screen reads `LiveSetTracker`; the logbook reads `SessionStatsBuilder`.
/// They must describe the same sets, including how an `unsure` gap is charged.
@Suite("LiveDerivedAgreement")
struct LiveDerivedAgreementTests {
    @Test func unsureTimeoutChargesTheGapToInactiveOnBothSides() {
        let events = [
            event(DetectionCodes.inactive, at: 0, id: "start"),
            event(DetectionCodes.riding, at: 10, id: "enter"),
            event(DetectionCodes.unsure, at: 100, id: "unsure"),
            event(DetectionCodes.inactive, at: 160, id: "timeout"),
        ]
        let live = liveSetDurations(events, stopAt: 200)
        let derived = derivedSets(events, stopAt: 200)

        #expect(derived.setCount == 1)
        #expect(live.count == derived.setCount)
        // Set ran 10 s → 100 s; the 60 s unsure window belongs to neither side's set.
        #expect(derived.ridingDuration == 90)
        #expect(live.riding == derived.ridingDuration)
    }

    @Test func lookbackToInactiveAgreesOnBothSides() {
        // Engine backdates a lookback-inactive revision to the unsure start, so both sides end
        // the set where the evidence stopped.
        let events = [
            event(DetectionCodes.inactive, at: 0, id: "start"),
            event(DetectionCodes.riding, at: 10, id: "enter"),
            event(DetectionCodes.unsure, at: 100, id: "unsure"),
            event(DetectionCodes.inactive, at: 100, id: "lookback", supersedesId: "unsure"),
        ]
        let live = liveSetDurations(events, stopAt: 200)
        let derived = derivedSets(events, stopAt: 200)

        #expect(derived.setCount == 1)
        #expect(live.count == derived.setCount)
        #expect(derived.ridingDuration == 90)
        #expect(live.riding == derived.ridingDuration)
    }

    @Test func lookbackBackToRidingKeepsOneContinuousSet() {
        let events = [
            event(DetectionCodes.inactive, at: 0, id: "start"),
            event(DetectionCodes.riding, at: 10, id: "enter"),
            event(DetectionCodes.unsure, at: 100, id: "unsure"),
            event(DetectionCodes.riding, at: 120, id: "lookback", supersedesId: "unsure"),
            event(DetectionCodes.inactive, at: 200, id: "exit"),
        ]
        let live = liveSetDurations(events, stopAt: 240)
        let derived = derivedSets(events, stopAt: 240)

        #expect(derived.setCount == 1)
        #expect(live.count == 1)
        // Superseded unsure line is dropped, so the gap stays inside the one set: 10 s → 200 s.
        #expect(derived.ridingDuration == 190)
        #expect(live.riding == derived.ridingDuration)
    }

    @Test func sessionStoppedWhileUnsureAgreesOnBothSides() {
        let events = [
            event(DetectionCodes.inactive, at: 0, id: "start"),
            event(DetectionCodes.riding, at: 10, id: "enter"),
            event(DetectionCodes.unsure, at: 100, id: "unsure"),
        ]
        let live = liveSetDurations(events, stopAt: 130)
        let derived = derivedSets(events, stopAt: 130)

        #expect(derived.setCount == 1)
        #expect(live.count == 1)
        #expect(derived.ridingDuration == 90)
        #expect(live.riding == derived.ridingDuration)
    }

    @Test func plainExitAgreesOnBothSides() {
        let events = [
            event(DetectionCodes.inactive, at: 0, id: "start"),
            event(DetectionCodes.riding, at: 10, id: "enter"),
            event(DetectionCodes.inactive, at: 70, id: "exit"),
            event(DetectionCodes.riding, at: 100, id: "enter2"),
            event(DetectionCodes.inactive, at: 130, id: "exit2"),
        ]
        let live = liveSetDurations(events, stopAt: 160)
        let derived = derivedSets(events, stopAt: 160)

        #expect(derived.setCount == 2)
        #expect(live.count == 2)
        #expect(derived.ridingDuration == 90)
        #expect(live.riding == derived.ridingDuration)
    }
}
