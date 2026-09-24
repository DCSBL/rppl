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
