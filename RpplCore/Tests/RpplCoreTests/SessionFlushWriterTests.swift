import Foundation
import Testing
@testable import RpplCore

/// The Watch flush loop appends the buffered streams every couple of seconds for the whole
/// session. Field session 2026-10-03: every flush after the first failed and the session kept
/// only its first batch. These tests drive the same writer the Watch uses.
@Suite("SessionFlushWriter", .serialized)
struct SessionFlushWriterTests {
    private func flush(
        _ session: TempSession,
        locations: [Int] = [],
        health: [Int] = [],
        water: [Int] = [],
        battery: [Int] = []
    ) -> FlushOutcome {
        SessionFlushWriter.write(
            locations: locations.map { Samples.location($0) },
            health: health.map { Samples.health($0) },
            water: water.map { Samples.water($0) },
            battery: battery.map { Samples.battery($0) },
            store: session.store,
            sessionId: session.sessionId
        )
    }

    @Test func everyFlushOfALongSessionLands() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        for batch in 0..<50 {
            let seconds = Array(batch * 4..<(batch * 4 + 4))
            let outcome = flush(
                session,
                locations: seconds,
                health: seconds,
                water: batch.isMultiple(of: 10) ? [batch * 4] : [],
                battery: batch.isMultiple(of: 15) ? [batch * 4] : []
            )
            #expect(outcome.failed.isEmpty, "flush \(batch): \(outcome.error ?? "")")
            #expect(outcome.error == nil)
        }
        let id = session.sessionId
        let locations = try session.store.readLocationSamples(sessionId: id)
        #expect(locations.count == 200)
        #expect(locations.map(\.timestamp) == (0..<200).map { Samples.time($0) })
        #expect(try session.store.readHealthSamples(sessionId: id).count == 200)
        #expect(try session.store.readWaterTemperatureSamples(sessionId: id).count == 5)
        #expect(try session.store.readBatterySamples(sessionId: id).count == 4)
    }

    @Test func outcomeReportsPackageSize() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let outcome = flush(session, locations: [0, 1])
        #expect((outcome.byteSize ?? 0) > 0)
    }

    @Test func emptyStreamsAreNotCreated() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let outcome = flush(session, locations: [0])
        #expect(outcome.failed.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: session.directory.path)
        #expect(names.contains("location-000.jsonl"))
        #expect(!names.contains("health-000.jsonl"))
        #expect(!names.contains("water-000.jsonl"))
        #expect(!names.contains("battery-000.jsonl"))
    }

    @Test func oneFailingStreamDoesNotCostTheOthers() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        _ = flush(session, locations: [0], health: [0], battery: [0])
        try session.makeUnwritable("health-000.jsonl")

        let outcome = flush(session, locations: [1], health: [1], battery: [1])

        #expect(outcome.failed == [.health])
        #expect(outcome.error != nil)
        let id = session.sessionId
        #expect(try session.store.readLocationSamples(sessionId: id).count == 2)
        #expect(try session.store.readBatterySamples(sessionId: id).count == 2)
        #expect(try session.store.readHealthSamples(sessionId: id).count == 1)
    }

    @Test func everyStreamFailingIsReportedPerStream() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        _ = flush(session, locations: [0], health: [0], water: [0], battery: [0])
        for name in ["location-000.jsonl", "health-000.jsonl", "water-000.jsonl", "battery-000.jsonl"] {
            try session.makeUnwritable(name)
        }

        let outcome = flush(session, locations: [1], health: [1], water: [1], battery: [1])

        #expect(outcome.failed == Set(FlushStream.allCases))
    }

    @Test func requeuedBatchLandsOnceAndInOrderOnceTheStreamRecovers() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        _ = flush(session, health: [0])
        try session.makeUnwritable("health-000.jsonl")

        // The Watch buffers (1, 2), the write fails, (3, 4) arrive, the failed batch goes back in
        // front, and the next flush must write 1…4 exactly once.
        var buffer = [Samples.health(1), Samples.health(2)]
        let failedBatch = buffer
        let failed = SessionFlushWriter.write(
            locations: [], health: buffer, water: [], battery: [],
            store: session.store, sessionId: session.sessionId
        )
        #expect(failed.failed == [.health])
        buffer = SampleRequeue.merge(
            failed: failedBatch,
            before: [Samples.health(3), Samples.health(4)],
            cap: SampleRequeue.healthCap
        )

        try session.makeWritable("health-000.jsonl")
        let recovered = SessionFlushWriter.write(
            locations: [], health: buffer, water: [], battery: [],
            store: session.store, sessionId: session.sessionId
        )

        #expect(recovered.failed.isEmpty)
        let stored = try session.store.readHealthSamples(sessionId: session.sessionId)
        #expect(stored.map(\.timestamp) == (0...4).map { Samples.time($0) })
    }

    @Test func unknownSessionFailsEveryStreamWithoutThrowing() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let outcome = SessionFlushWriter.write(
            locations: [Samples.location(0)], health: [Samples.health(0)], water: [], battery: [],
            store: session.store, sessionId: UUID().uuidString
        )
        #expect(outcome.failed == [.locations, .health])
        #expect(outcome.byteSize == nil)
    }
}
