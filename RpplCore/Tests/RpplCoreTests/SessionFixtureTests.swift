import Foundation
import Testing
@testable import RpplCore

/// Real park-day sessions with hand-written ground truth (`annotations`). Each annotation kind
/// maps to one test below, so a new export becomes a regression test by adding annotations —
/// see `Fixtures/Sessions/README.md` and `scripts/make-session-fixture.py`.
struct SessionFixture: Decodable {
    struct Annotation: Decodable {
        var id: String
        /// `set`, `badFix`, `lateDelivery`, `noGps`.
        var kind: String
        /// `good`, `bad`, `missing` — what the recording or live detection did, not the test.
        var verdict: String
        var note: String
        var start: Date?
        var end: Date?
        var at: Date?
        var arrivedAfter: Date?
        var toleranceSeconds: TimeInterval?
        var liveStart: Date?
        var liveEnd: Date?
    }

    var name: String
    var description: String
    var exportWasDoubled: Bool
    var manifest: SessionManifest
    var annotations: [Annotation]
    var recordedDetections: [DetectionEvent]
    /// On-disk (arrival) order, repeated and late fixes included.
    var locations: [LocationSample]

    func annotations(kind: String) -> [Annotation] {
        annotations.filter { $0.kind == kind }
    }

    static let names = [
        "downunder-2026-09-30",
    ]

    static func load(_ name: String) throws -> SessionFixture {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/Sessions"
        ) else {
            throw SessionFixtureError.missing(name)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionFixture.self, from: Data(contentsOf: url))
    }

    /// What the logbook shows when every fix reaches the engine in time order.
    func timeOrderedStats() -> SessionStats {
        SessionStatsBuilder.build(
            manifest: manifest,
            detections: DetectionEngine.replay(locations: locations),
            locations: locations,
            health: []
        )
    }

    /// Live Watch replay: fixes in the order they were recorded, with 1 Hz heartbeats on a wall
    /// clock that never runs backwards. A late fix arrives when the clock has moved past it.
    func arrivalOrderEvents() -> [DetectionEvent] {
        var ticks: [DetectionTick] = []
        var wall: Date?
        for sample in locations {
            let arrival = max(wall ?? sample.timestamp, sample.timestamp)
            if let wall {
                var next = wall.addingTimeInterval(1)
                while next < arrival {
                    ticks.append(.heartbeat(at: next))
                    next = next.addingTimeInterval(1)
                }
            }
            ticks.append(
                DetectionTick(
                    timestamp: sample.timestamp,
                    speedMps: sample.speed,
                    horizontalAccuracy: sample.horizontalAccuracy
                )
            )
            wall = arrival
        }
        return DetectionEngine.replay(ticks: ticks)
    }
}

enum SessionFixtureError: Error {
    case missing(String)
    case incomplete(String)
}

@Suite("SessionFixtures")
struct SessionFixtureTests {
    @Test(arguments: SessionFixture.names)
    func annotatedSetsMatchTimeOrderedReplay(name: String) throws {
        let fixture = try SessionFixture.load(name)
        let expected = fixture.annotations(kind: "set")
        let sets = fixture.timeOrderedStats().sets
        #expect(sets.count == expected.count, "\(name): \(sets.count) sets, annotated \(expected.count)")

        for annotation in expected {
            guard let start = annotation.start else { throw SessionFixtureError.incomplete(annotation.id) }
            let tolerance = annotation.toleranceSeconds ?? 3
            let matches = sets.filter { abs($0.startedAt.timeIntervalSince(start)) <= tolerance }
            #expect(matches.count == 1, "\(name) \(annotation.id): no single set starting at \(start) ±\(tolerance)s")
            if let end = annotation.end, let set = matches.first {
                #expect(
                    abs(set.endedAt.timeIntervalSince(end)) <= tolerance,
                    "\(name) \(annotation.id): ends \(set.endedAt), annotated \(end) ±\(tolerance)s"
                )
            }
        }
    }

    /// Fixes held back and delivered in a burst must not re-open a set in the past.
    @Test(arguments: SessionFixture.names)
    func lateDeliveriesNeverRewindTheLiveEngine(name: String) throws {
        let fixture = try SessionFixture.load(name)
        let late = fixture.annotations(kind: "lateDelivery")
        guard !late.isEmpty else { return }

        var latest: Date?
        for event in fixture.arrivalOrderEvents() {
            if event.detectorId == "ride_enter" {
                if let latest {
                    #expect(event.timestamp >= latest, "\(name): ride_enter at \(event.timestamp) after \(latest)")
                }
                for window in late {
                    guard let start = window.start, let end = window.end else { continue }
                    #expect(
                        !(start...end).contains(event.timestamp),
                        "\(name) \(window.id): ride_enter inside late window at \(event.timestamp)"
                    )
                }
            }
            latest = max(latest ?? event.timestamp, event.timestamp)
        }
    }

    @Test(arguments: SessionFixture.names)
    func lateDeliveriesAreDroppedBeforeDetection(name: String) throws {
        let fixture = try SessionFixture.load(name)
        for window in fixture.annotations(kind: "lateDelivery") {
            guard let start = window.start, let end = window.end, let arrivedAfter = window.arrivedAfter else {
                throw SessionFixtureError.incomplete(window.id)
            }
            var sequencer = LocationFixSequencer()
            var arrived = false
            var late = 0
            var dropped = 0
            for sample in fixture.locations {
                let accepted = sequencer.accept(sample.timestamp)
                if sample.timestamp == arrivedAfter { arrived = true }
                guard arrived, (start...end).contains(sample.timestamp) else { continue }
                late += 1
                if !accepted { dropped += 1 }
            }
            #expect(late > 0, "\(name) \(window.id): no fixes arrived after \(arrivedAfter)")
            #expect(dropped == late, "\(name) \(window.id): \(dropped) of \(late) late fixes dropped")
        }
    }

    @Test(arguments: SessionFixture.names)
    func badFixesStayOffMapTracks(name: String) throws {
        let fixture = try SessionFixture.load(name)
        let sets = fixture.timeOrderedStats().sets
        let sorted = fixture.locations.sorted { $0.timestamp < $1.timestamp }
        for annotation in fixture.annotations(kind: "badFix") {
            guard let at = annotation.at else { throw SessionFixtureError.incomplete(annotation.id) }
            let bad = fixture.locations.filter {
                $0.timestamp == at && $0.horizontalAccuracy > DetectionThresholds.default.maxHorizontalAccuracyM
            }
            #expect(!bad.isEmpty, "\(name) \(annotation.id): no low-accuracy fix at \(at)")
            guard let set = sets.first(where: { $0.startedAt <= at && at <= $0.endedAt }) else {
                Issue.record("\(name) \(annotation.id): \(at) is not inside a set")
                continue
            }
            let track = SetLocationFilter.trackSamples(in: sorted, from: set.startedAt, to: set.endedAt)
            #expect(track.count >= 2)
            for sample in bad {
                #expect(!track.contains(sample), "\(name) \(annotation.id): bad fix drawn on the map")
            }
        }
    }

    /// A gap in the recording, not a detection bug: nothing usable to detect from, and the engine
    /// must not invent a set there.
    @Test(arguments: SessionFixture.names)
    func noGpsWindowsHaveNothingToDetect(name: String) throws {
        let fixture = try SessionFixture.load(name)
        let sets = fixture.timeOrderedStats().sets
        for window in fixture.annotations(kind: "noGps") {
            guard let start = window.start, let end = window.end else { throw SessionFixtureError.incomplete(window.id) }
            let usable = fixture.locations.filter {
                (start...end).contains($0.timestamp)
                    && $0.speed != nil
                    && $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= DetectionThresholds.default.maxHorizontalAccuracyM
            }
            #expect(usable.isEmpty, "\(name) \(window.id): \(usable.count) usable fixes")
            #expect(!sets.contains { (start...end).contains($0.startedAt) }, "\(name) \(window.id): set invented")
        }
    }
}

/// What went wrong live on 2026-09-30, kept as a record next to the fixed behaviour above.
@Suite("DownUnder20260930")
struct DownUnder20260930Tests {
    @Test func liveDetectionsCarryTheGhostSet() throws {
        let fixture = try SessionFixture.load("downunder-2026-09-30")
        let set10 = try #require(fixture.annotations.first { $0.id == "set-10" })
        let liveEnd = try #require(set10.liveEnd)
        let recorded = fixture.recordedDetections
        let timeoutIndex = try #require(recorded.firstIndex {
            $0.detectorId == "unsure_timeout" && $0.timestamp == liveEnd
        })
        // Written after the timeout, stamped before it: the late batch re-opened a set.
        let ghost = recorded[(timeoutIndex + 1)...].first { $0.detectorId == "ride_enter" }
        #expect(ghost.map { $0.timestamp < liveEnd } == true)
    }

    @Test func exportWasDoubledOnThePhone() throws {
        let fixture = try SessionFixture.load("downunder-2026-09-30")
        #expect(fixture.exportWasDoubled)
        #expect(fixture.recordedDetections.count == 32)
        #expect(fixture.locations.count == 2_181)
    }

    /// Repeats and reorders were not limited to set 10: the awaited route insert shuffled fixes
    /// all session long.
    @Test func manyFixesArrivedRepeatedOrOutOfOrder() throws {
        let fixture = try SessionFixture.load("downunder-2026-09-30")
        var sequencer = LocationFixSequencer()
        for sample in fixture.locations {
            _ = sequencer.accept(sample.timestamp)
        }
        #expect(sequencer.droppedCount == 217)
    }
}
