import Foundation
import Testing
@testable import RpplCore

@Suite("MotionRecordingPolicy")
struct MotionRecordingPolicyTests {
    private let plenty: Int64 = 4 * 1024 * 1024 * 1024

    @Test func recordsNormally() {
        #expect(MotionRecordingPolicy.decide(elapsed: 3600, motionBytes: 1_000_000, freeBytes: plenty) == .record)
        #expect(MotionRecordingPolicy.decide(elapsed: 0, motionBytes: 0, freeBytes: nil) == .record)
    }

    @Test func longSessionStopsMotionFirst() {
        let decision = MotionRecordingPolicy.decide(
            elapsed: MotionRecordingPolicy.maxSessionDuration,
            motionBytes: 1_000_000,
            freeBytes: plenty
        )
        #expect(decision == .stop(reason: MotionRecordingPolicy.Reason.longSession))
    }

    @Test func fileBudgetStopsMotion() {
        let decision = MotionRecordingPolicy.decide(
            elapsed: 600,
            motionBytes: MotionRecordingPolicy.maxCompressedBytes,
            freeBytes: plenty
        )
        #expect(decision == .stop(reason: MotionRecordingPolicy.Reason.fileBudget))
    }

    @Test func lowStorageStopsAndCriticalStorageDrops() {
        #expect(
            MotionRecordingPolicy.decide(elapsed: 60, motionBytes: 0, freeBytes: MotionRecordingPolicy.stopBelowFreeBytes - 1)
                == .stop(reason: MotionRecordingPolicy.Reason.lowStorage)
        )
        #expect(
            MotionRecordingPolicy.decide(elapsed: 60, motionBytes: 0, freeBytes: MotionRecordingPolicy.dropBelowFreeBytes - 1)
                == .dropRecorded(reason: MotionRecordingPolicy.Reason.storageCritical)
        )
    }

    /// Field data 2026-09-30: ~0.94 MB compressed motion per hour at ~25% riding. Even an all-riding
    /// hour (~3.5 MB) keeps a 4 h cap under the file budget, and 30 s frames stay far under the
    /// import frame limit for a whole day.
    @Test func boundsFitAFullDayUnderImportLimits() {
        let framesPerDay = Int(24 * 3600 / MotionRecordingPolicy.frameInterval)
        #expect(framesPerDay < CompressedJSONLFrames.maxFrameCount)
        // Field compression ratio ~3.6x: the budget decodes under the import bound.
        #expect(Double(MotionRecordingPolicy.maxCompressedBytes) * 3.6 < Double(CompressedJSONLFrames.maxTotalDecodedBytes))
        #expect(MotionRecordingPolicy.dropBelowFreeBytes < MotionRecordingPolicy.stopBelowFreeBytes)
    }
}

@Suite("MotionStorage")
struct MotionStorageTests {
    @Test func deleteMotionAndMarkStopped() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("motion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)
        let sample = MotionSample(
            timestamp: Date(),
            userAccelX: 0.1, userAccelY: 0, userAccelZ: 0,
            rotationX: 0, rotationY: 0, rotationZ: 0,
            pitch: 0, roll: 0, yaw: 0
        )
        try store.appendMotionSamples([sample], sessionId: manifest.sessionId)
        #expect(try store.motionByteSize(sessionId: manifest.sessionId) > 0)

        try store.deleteMotion(sessionId: manifest.sessionId)
        #expect(try store.motionByteSize(sessionId: manifest.sessionId) == 0)
        #expect(try store.readMotionFrameData(sessionId: manifest.sessionId) == nil)

        let at = Date(timeIntervalSince1970: 1_800_000_000)
        try store.markMotionStopped(reason: MotionRecordingPolicy.Reason.storageCritical, at: at, sessionId: manifest.sessionId)
        try store.markMotionStopped(reason: MotionRecordingPolicy.Reason.longSession, at: Date(), sessionId: manifest.sessionId)
        let read = try store.readManifest(sessionId: manifest.sessionId)
        #expect(read.motionStoppedReason == MotionRecordingPolicy.Reason.storageCritical)
        #expect(read.motionStoppedAt == at)
        #expect(store.availableCapacityBytes() != nil)
    }
}
