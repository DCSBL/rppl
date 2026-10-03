import Foundation
import Testing
@testable import RpplCore

/// A whole session through the same store calls the Watch and phone make: record with repeated
/// flushes, finish, transfer, import on the phone, ack, prune. Field session 2026-10-03 lost its
/// streams to one bug in this chain and could not sync because of another; each unit on its own
/// passed. These tests exist to fail when any link in the chain breaks.
@Suite("RecordingPipeline", .serialized)
struct RecordingPipelineTests {
    private let futureCode = "future_trick_x"

    /// Samples that went into the Watch store, to compare with what the phone ends up with.
    private struct RecordedCounts {
        var locations = 0
        var health = 0
        var water = 0
        var battery = 0
        var motionFrames = 0
    }

    /// Records `minutes` of session: a flush every 4 s (all streams), a motion frame every 30 s,
    /// detections around a set. Returns the sample counts that went in.
    @discardableResult
    private func record(
        _ session: TempSession,
        minutes: Int = 10,
        extraDetection: String? = nil
    ) throws -> RecordedCounts {
        let store = session.store
        let id = session.sessionId
        try store.appendDetection(Samples.detection(DetectionCodes.inactive, second: 0, detectorId: "session_start"), sessionId: id)
        var counts = RecordedCounts()
        let seconds = minutes * 60
        for second in stride(from: 0, to: seconds, by: 4) {
            let outcome = SessionFlushWriter.write(
                locations: (second..<(second + 4)).map { Samples.location($0) },
                health: [Samples.health(second)],
                water: second % 60 == 0 ? [Samples.water(second)] : [],
                battery: second % 60 == 0 ? [Samples.battery(second)] : [],
                store: store,
                sessionId: id
            )
            #expect(outcome.failed.isEmpty, "flush at \(second)s failed: \(outcome.error ?? "")")
            counts.locations += 4
            counts.health += 1
            if second % 60 == 0 { counts.water += 1; counts.battery += 1 }
            if second % 30 == 0 {
                try store.appendMotionSamples((second..<(second + 30)).map { Samples.motion($0) }, sessionId: id)
                counts.motionFrames += 1
            }
            if second == 60 { try store.appendDetection(Samples.detection(DetectionCodes.riding, second: 60), sessionId: id) }
            if second == 300 { try store.appendDetection(Samples.detection(DetectionCodes.inactive, second: 300), sessionId: id) }
        }
        if let extraDetection {
            try store.appendDetection(Samples.detection(extraDetection, second: 120), sessionId: id)
        }
        try store.markReadyToTransfer(sessionId: id, endedAt: Samples.time(seconds))
        return counts
    }

    private func transferToPhone(_ session: TempSession, phoneRoot: URL) throws -> SessionTransferPackage {
        try session.store.markTransferring(sessionId: session.sessionId)
        let zipDir = session.root.appendingPathComponent("outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: zipDir, withIntermediateDirectories: true)
        let url = try session.store.zipSessionForTransfer(sessionId: session.sessionId, to: zipDir)
        // Exactly what the phone does on receipt.
        let package = try SessionImportLimits.decodeTransferPackage(
            from: SessionImportLimits.readBoundedFile(at: url)
        )
        try session.store.importTransferPackage(package, intoPhoneStore: phoneRoot)
        return package
    }

    private func phoneRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-phone-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func recordedSessionArrivesOnThePhoneComplete() throws {
        let session = try TempSession.make()
        let phoneRoot = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phoneRoot) }
        let counts = try record(session, minutes: 10, extraDetection: futureCode)
        let id = session.sessionId

        _ = try transferToPhone(session, phoneRoot: phoneRoot)

        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.listSessionIDs() == [id])
        #expect(try phone.readLocationSamples(sessionId: id).count == counts.locations)
        #expect(try phone.readHealthSamples(sessionId: id).count == counts.health)
        #expect(try phone.readWaterTemperatureSamples(sessionId: id).count == counts.water)
        #expect(try phone.readBatterySamples(sessionId: id).count == counts.battery)
        #expect(try phone.readMotionSamples(sessionId: id).count == counts.motionFrames * 30)
        #expect(try phone.readLocationSamples(sessionId: id).map(\.timestamp)
            == (0..<(10 * 60)).map { Samples.time($0) })
        let manifest = try phone.readManifest(sessionId: id)
        #expect(manifest.transferState == .acknowledged)
        #expect(manifest.endedAt == Samples.time(600))
        #expect(try phone.readDerivedView(sessionId: id) != nil)
    }

    @Test func unknownDetectionCodesSurviveTheWholeChain() throws {
        let session = try TempSession.make()
        let phoneRoot = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phoneRoot) }
        try record(session, minutes: 5, extraDetection: futureCode)

        _ = try transferToPhone(session, phoneRoot: phoneRoot)

        let phone = SessionFileStore(rootURL: phoneRoot)
        let codes = try phone.readDetections(sessionId: session.sessionId).map(\.code)
        #expect(codes.contains(futureCode))
        #expect(codes == (try session.store.readDetections(sessionId: session.sessionId)).map(\.code))
    }

    @Test func aTransferThatArrivesTwiceDoesNotDuplicateAnything() throws {
        let session = try TempSession.make()
        let phoneRoot = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phoneRoot) }
        let counts = try record(session, minutes: 5)
        let package = try transferToPhone(session, phoneRoot: phoneRoot)

        // WatchConnectivity redelivers when the ack got lost.
        try session.store.importTransferPackage(package, intoPhoneStore: phoneRoot)

        let phone = SessionFileStore(rootURL: phoneRoot)
        let id = session.sessionId
        #expect(try phone.readLocationSamples(sessionId: id).count == counts.locations)
        #expect(try phone.readHealthSamples(sessionId: id).count == counts.health)
        #expect(try phone.readDetections(sessionId: id).count
            == (try session.store.readDetections(sessionId: id)).count)
    }

    @Test func prunedWatchSessionKeepsItsSummaryAndIsNeverResent() throws {
        let session = try TempSession.make()
        let phoneRoot = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phoneRoot) }
        try record(session, minutes: 5)
        _ = try transferToPhone(session, phoneRoot: phoneRoot)
        let id = session.sessionId
        let store = session.store

        #expect(try store.markAcknowledged(sessionId: id) == true)
        #expect(try store.markAcknowledged(sessionId: id) == false)
        _ = try store.ensureDerivedView(sessionId: id)
        try store.pruneRawStreams(sessionId: id)

        #expect(!store.hasRawStreams(sessionId: id))
        #expect(try store.readManifest(sessionId: id).transferState == .acknowledged)
        #expect(try store.readDerivedView(sessionId: id) != nil)
        #expect(try store.sessionsNeedingTransfer().isEmpty)
        #expect(throws: SessionStoreError.self) {
            try store.zipSessionForTransfer(sessionId: id, to: session.root)
        }
        // The phone still has every sample.
        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.readLocationSamples(sessionId: id).count == 300)
    }

    @Test func aSessionKilledMidRecordingStillReachesThePhone() throws {
        let session = try TempSession.make()
        let phoneRoot = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phoneRoot) }
        let store = session.store
        let id = session.sessionId
        // Recording stops abruptly: no markReadyToTransfer, torn tails on a JSONL and the motion file.
        try store.appendDetection(Samples.detection(DetectionCodes.inactive, second: 0, detectorId: "session_start"), sessionId: id)
        for second in stride(from: 0, to: 60, by: 4) {
            _ = SessionFlushWriter.write(
                locations: (second..<(second + 4)).map { Samples.location($0) },
                health: [Samples.health(second)], water: [], battery: [],
                store: store, sessionId: id
            )
        }
        try store.appendMotionSamples((0..<30).map { Samples.motion($0) }, sessionId: id)
        try appendRaw(Array(#"{"timestamp":"2026-09-21T14:1"#.utf8), to: "location-000.jsonl", session: session)
        try appendRaw([0x00, 0x00, 0x02, 0x00, 0x78, 0x9C], to: "motion-000.jsonl.zlib", session: session)

        // Next launch: recover orphaned recordings, then the normal transfer.
        #expect(store.recoverOrphanedRecordings(activeSessionId: nil) == [id])
        _ = try transferToPhone(session, phoneRoot: phoneRoot)

        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.readLocationSamples(sessionId: id).count == 60)
        #expect(try phone.readMotionSamples(sessionId: id).count == 30)
        #expect(try phone.readManifest(sessionId: id).transferState == .acknowledged)
    }

    private func appendRaw(_ bytes: [UInt8], to name: String, session: TempSession) throws {
        let handle = try FileHandle(forWritingTo: session.file(name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(bytes))
    }
}
