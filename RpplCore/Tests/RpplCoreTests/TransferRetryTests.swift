import Foundation
import Testing
@testable import RpplCore

private func tempStore() -> (SessionFileStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("retry-\(UUID().uuidString)", isDirectory: true)
    return (SessionFileStore(rootURL: root), root)
}

private func manifest(next: Date? = nil, state: SessionManifest.TransferState = .readyToTransfer) -> SessionManifest {
    SessionManifest(
        testerId: "t",
        appVersion: "1.0",
        buildNumber: "1",
        watchModel: "Watch",
        systemVersion: "26.0",
        transferState: state,
        nextTransferAttemptAt: next
    )
}

@Suite("TransferRetryPolicy")
struct TransferRetryPolicyTests {
    @Test func delaysGrowAndCap() {
        #expect(TransferRetryPolicy.delay(afterAttempt: 0) == 0)
        #expect(TransferRetryPolicy.delay(afterAttempt: 1) == 60)
        #expect(TransferRetryPolicy.delay(afterAttempt: 3) == 30 * 60)
        #expect(TransferRetryPolicy.delay(afterAttempt: 99) == 24 * 3600)
    }

    @Test func dueFiltersBackoffAndState() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = manifest()
        let waiting = manifest(next: now.addingTimeInterval(60))
        let ready = manifest(next: now.addingTimeInterval(-1))
        let acked = manifest(state: .acknowledged)
        let recording = manifest(state: .recording)
        let due = TransferRetryPolicy.due([fresh, waiting, ready, acked, recording], now: now)
        #expect(due.map(\.sessionId) == [fresh.sessionId, ready.sessionId])
    }
}

@Suite("TransferBookkeeping")
struct TransferBookkeepingTests {
    /// A retry used to re-run `markReadyToTransfer`, which stamps `endedAt = now` and stretched
    /// the session by however long the transfer took to fail.
    @Test func requeueKeepsEndedAt() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = manifest(state: .recording)
        try store.createSession(manifest: session)
        let ended = Date(timeIntervalSince1970: 1_800_000_000)
        try store.markReadyToTransfer(sessionId: session.sessionId, endedAt: ended)
        try store.markTransferring(sessionId: session.sessionId)

        try store.requeueForTransfer(sessionId: session.sessionId)
        let read = try store.readManifest(sessionId: session.sessionId)
        #expect(read.transferState == .readyToTransfer)
        #expect(read.endedAt == ended)
    }

    @Test func attemptsScheduleBackoffAndFailuresKeepSession() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = manifest(state: .readyToTransfer)
        try store.createSession(manifest: session)
        let at = Date(timeIntervalSince1970: 1_800_000_000)

        try store.recordTransferAttempt(sessionId: session.sessionId, at: at)
        try store.recordTransferAttempt(sessionId: session.sessionId, at: at)
        var read = try store.readManifest(sessionId: session.sessionId)
        #expect(read.transferAttempts == 2)
        #expect(read.nextTransferAttemptAt == at.addingTimeInterval(TransferRetryPolicy.delay(afterAttempt: 2)))

        try store.markTransferring(sessionId: session.sessionId)
        try store.recordTransferFailure(sessionId: session.sessionId, reason: "motion: tooManyFrames")
        read = try store.readManifest(sessionId: session.sessionId)
        #expect(read.transferState == .readyToTransfer)
        #expect(read.lastTransferError == "motion: tooManyFrames")
        #expect(try store.listSessionIDs().contains(session.sessionId))
    }

    @Test func failureNeverUndoesAnAck() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = manifest(state: .acknowledged)
        try store.createSession(manifest: session)
        try store.recordTransferFailure(sessionId: session.sessionId, reason: "late nack")
        try store.requeueForTransfer(sessionId: session.sessionId)
        #expect(try store.readManifest(sessionId: session.sessionId).transferState == .acknowledged)
    }

    @Test func importFailureReasonIsShortAndSpecific() {
        #expect(SessionImportFailure.reason(for: CompressedJSONLFrameError.tooManyFrames) == "motion: tooManyFrames")
        let long = SessionStoreError.ioFailure(String(repeating: "x", count: 1_000))
        #expect(SessionImportFailure.reason(for: long).count == SessionImportFailure.maxReasonLength)
    }
}

@Suite("TransferStateMachine")
struct TransferStateMachineTests {
    @Test func acknowledgedIsTerminal() {
        typealias State = SessionManifest.TransferState
        for next in [State.recording, .readyToTransfer, .transferring] {
            #expect(!TransferStateMachine.isAllowed(from: .acknowledged, to: next))
        }
        #expect(TransferStateMachine.isAllowed(from: .acknowledged, to: .acknowledged))
        #expect(TransferStateMachine.isAllowed(from: .transferring, to: .readyToTransfer))
        #expect(TransferStateMachine.isAllowed(from: .readyToTransfer, to: .transferring))
    }

    @Test func acknowledgedSessionCannotRegress() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = manifest(state: .readyToTransfer)
        try store.createSession(manifest: session)
        try store.markAcknowledged(sessionId: session.sessionId)

        try store.markTransferring(sessionId: session.sessionId)
        try store.requeueForTransfer(sessionId: session.sessionId)
        try store.markReadyToTransfer(sessionId: session.sessionId, endedAt: Date())
        #expect(try store.readManifest(sessionId: session.sessionId).transferState == .acknowledged)
    }

    @Test func zipRefusesAcknowledgedSessions() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = manifest(state: .readyToTransfer)
        try store.createSession(manifest: session)
        try store.appendDetection(
            DetectionEvent(code: DetectionCodes.inactive, reason: "r", detectorId: "r"),
            sessionId: session.sessionId
        )
        try store.markAcknowledged(sessionId: session.sessionId)
        #expect(throws: SessionStoreError.notTransferable("already acknowledged")) {
            try store.zipSessionForTransfer(sessionId: session.sessionId, to: root)
        }
    }

    @Test func unackedSessionWithoutRawStreamsStillZipsSoPendingClears() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = manifest(state: .readyToTransfer)
        let dir = try store.createSession(manifest: empty)
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path)
        where name != "manifest.json" {
            try FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        #expect(!store.hasRawStreams(sessionId: empty.sessionId))
        let url = try store.zipSessionForTransfer(sessionId: empty.sessionId, to: root)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func emptyImportKeepsExistingPhoneCopy() throws {
        let (watch, watchRoot) = tempStore()
        let (_, phoneRoot) = tempStore()
        defer {
            try? FileManager.default.removeItem(at: watchRoot)
            try? FileManager.default.removeItem(at: phoneRoot)
        }
        let session = manifest(state: .readyToTransfer)
        try watch.createSession(manifest: session)
        try watch.appendDetection(
            DetectionEvent(code: DetectionCodes.inactive, reason: "r", detectorId: "r"),
            sessionId: session.sessionId
        )
        let full = try watch.buildTransferPackage(sessionId: session.sessionId)
        try watch.importTransferPackage(full, intoPhoneStore: phoneRoot)

        let empty = SessionTransferPackage(
            manifest: session, detections: [], locations: [], motion: [], motionFramesZlib: nil,
            health: [], water: [], battery: [], derived: nil
        )
        try watch.importTransferPackage(empty, intoPhoneStore: phoneRoot)
        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.readDetections(sessionId: session.sessionId).count == 1)
    }
}
