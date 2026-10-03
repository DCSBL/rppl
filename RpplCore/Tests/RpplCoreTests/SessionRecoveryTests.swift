import Foundation
import Testing
@testable import RpplCore

@Suite("SessionRecovery", .serialized)
struct SessionRecoveryTests {
    private func makeStore() -> (SessionFileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-\(UUID().uuidString)", isDirectory: true)
        return (SessionFileStore(rootURL: root), root)
    }

    private func manifest(state: SessionManifest.TransferState = .recording) -> SessionManifest {
        var m = SessionManifest(
            testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "Watch7,1", systemVersion: "26.0"
        )
        m.transferState = state
        return m
    }

    @Test func filterSkipsActiveAndNonRecording() {
        let orphan = manifest()
        let active = manifest()
        let done = manifest(state: .acknowledged)
        let ids = SessionRecovery.orphanedRecordingIds(
            manifests: [orphan, active, done], activeSessionId: active.sessionId
        )
        #expect(ids == [orphan.sessionId])
    }

    @Test func finalizeMakesSessionTransferable() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = manifest()
        _ = try store.createSession(manifest: m)
        #expect(try store.sessionsNeedingTransfer().isEmpty)

        #expect(try store.finalizeOrphanedRecording(sessionId: m.sessionId))

        let loaded = try store.readManifest(sessionId: m.sessionId)
        #expect(loaded.transferState == .readyToTransfer)
        #expect(loaded.endedAt != nil)
        let last = (try store.readDetections(sessionId: m.sessionId)).last
        #expect(last?.detectorId == SessionRecovery.crashRecoveredDetectorId)
        #expect(last?.code == DetectionCodes.inactive)
        #expect(try store.sessionsNeedingTransfer().map(\.sessionId) == [m.sessionId])
    }

    @Test func recoveredSessionEndsAtTheLastRecordedSampleAndKeepsTheFinalSet() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let id = session.sessionId
        // `riding` entered at 60 s, then GPS kept coming for ten more minutes before the crash.
        try session.store.appendDetection(Samples.detection(DetectionCodes.riding, second: 60), sessionId: id)
        try session.store.appendLocationSamples((0...660).map { Samples.location($0) }, sessionId: id)

        #expect(try session.store.finalizeOrphanedRecording(sessionId: id))

        let manifest = try session.store.readManifest(sessionId: id)
        #expect(manifest.endedAt == Samples.time(660))
        let stats = try #require(try session.store.readDerivedView(sessionId: id)).stats
        #expect(stats.setCount == 1)
        #expect(abs(stats.ridingDuration - 600) < 1)
        #expect(stats.totalDistanceMeters > 0)
    }

    @Test func lastRecordedTimestampLooksAtEveryStreamButMotion() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let id = session.sessionId
        try session.store.appendDetection(Samples.detection(DetectionCodes.riding, second: 10), sessionId: id)
        try session.store.appendLocationSamples([Samples.location(20)], sessionId: id)
        try session.store.appendHealthSamples([Samples.health(30)], sessionId: id)
        try session.store.appendWaterTemperatureSamples([Samples.water(40)], sessionId: id)
        try session.store.appendBatterySamples([Samples.battery(50)], sessionId: id)
        try session.store.appendMotionSamples([Samples.motion(999)], sessionId: id)

        #expect(session.store.lastRecordedTimestamp(sessionId: id) == Samples.time(50))
    }

    @Test func aSessionWithNothingRecordedEndsAtItsStart() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        #expect(session.store.lastRecordedTimestamp(sessionId: session.sessionId) == nil)

        #expect(try session.store.finalizeOrphanedRecording(sessionId: session.sessionId))
        #expect(try session.store.readManifest(sessionId: session.sessionId).endedAt == Samples.t0)
    }

    @Test func finalizeIsIdempotentAndLeavesOthersAlone() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let orphan = manifest()
        let acked = manifest(state: .acknowledged)
        _ = try store.createSession(manifest: orphan)
        _ = try store.createSession(manifest: acked)

        #expect(store.recoverOrphanedRecordings(activeSessionId: nil) == [orphan.sessionId])
        #expect(store.recoverOrphanedRecordings(activeSessionId: nil).isEmpty)
        #expect(try store.readManifest(sessionId: acked.sessionId).transferState == .acknowledged)
        #expect(try store.readDetections(sessionId: orphan.sessionId).count == 1)
    }
}
