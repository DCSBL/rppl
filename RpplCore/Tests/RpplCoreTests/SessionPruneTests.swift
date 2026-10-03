import Foundation
import Testing
@testable import RpplCore

/// Pruning is the only place the Watch deletes recorded data, and only after the phone acked.
/// These tests pin which files count as raw, what must survive, and when it must refuse.
@Suite("Prune raw streams", .serialized)
struct SessionPruneTests {
    private static let rawFiles = [
        "detections.jsonl",
        "location-000.jsonl", "location-001.jsonl",
        "health-000.jsonl",
        "water-000.jsonl",
        "battery-000.jsonl",
        "motion-000.jsonl.zlib", "motion-001.jsonl.zlib",
        "motion-000.jsonl",
        "assumptions.jsonl", "labels.jsonl"
    ]

    private func ackedSession(withDerived: Bool = true) throws -> TempSession {
        let session = try TempSession.make(endedAt: Samples.time(60), state: .readyToTransfer)
        for name in Self.rawFiles {
            try Data("x\n".utf8).write(to: session.file(name))
        }
        _ = try session.store.markAcknowledged(sessionId: session.sessionId)
        if withDerived {
            try session.store.ensureDerivedView(sessionId: session.sessionId)
        }
        return session
    }

    @Test(arguments: SessionPruneTests.rawFiles)
    func eachRawStreamFileIsRecognizedAsRaw(name: String) throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        // Only manifest + this file: hasRawStreams is true exactly when the name counts as raw.
        for existing in try FileManager.default.contentsOfDirectory(atPath: session.directory.path)
        where existing != "manifest.json" {
            try FileManager.default.removeItem(at: session.file(existing))
        }
        #expect(!session.store.hasRawStreams(sessionId: session.sessionId))
        try Data("x\n".utf8).write(to: session.file(name))
        #expect(session.store.hasRawStreams(sessionId: session.sessionId), "\(name) not treated as raw")
    }

    @Test(arguments: ["manifest.json", "notes.txt", "photo.jpg", "location.jsonl", "motion-000.zlib", "derived"])
    func otherFilesAreNeverRaw(name: String) throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        for existing in try FileManager.default.contentsOfDirectory(atPath: session.directory.path)
        where existing != "manifest.json" {
            try FileManager.default.removeItem(at: session.file(existing))
        }
        if name != "manifest.json" {
            try Data("x".utf8).write(to: session.file(name))
        }
        #expect(!session.store.hasRawStreams(sessionId: session.sessionId))
    }

    @Test func pruneRemovesEveryRawStreamAndKeepsTheRest() throws {
        let session = try ackedSession()
        defer { session.cleanup() }
        try Data("keep".utf8).write(to: session.file("notes.txt"))

        try session.store.pruneRawStreams(sessionId: session.sessionId)

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: session.directory.path))
        #expect(remaining == ["manifest.json", "derived", "notes.txt"])
        #expect(try session.store.readDerivedView(sessionId: session.sessionId) != nil)
        #expect(try session.store.readManifest(sessionId: session.sessionId).transferState == .acknowledged)
    }

    @Test func pruneTwiceIsHarmless() throws {
        let session = try ackedSession()
        defer { session.cleanup() }
        try session.store.pruneRawStreams(sessionId: session.sessionId)
        try session.store.pruneRawStreams(sessionId: session.sessionId)
        #expect(!session.store.hasRawStreams(sessionId: session.sessionId))
    }

    @Test(arguments: [
        SessionManifest.TransferState.recording,
        .readyToTransfer,
        .transferring
    ])
    func pruneRefusesEverySessionThatIsNotAcknowledged(state: SessionManifest.TransferState) throws {
        let session = try TempSession.make(state: state)
        defer { session.cleanup() }
        try Data("x\n".utf8).write(to: session.file("location-000.jsonl"))
        try session.store.ensureDerivedView(sessionId: session.sessionId)

        #expect(throws: SessionStoreError.self) {
            try session.store.pruneRawStreams(sessionId: session.sessionId)
        }
        #expect(session.store.hasRawStreams(sessionId: session.sessionId))
    }

    @Test func pruneRefusesWithoutADerivedViewSoTheSummarySurvives() throws {
        let session = try ackedSession(withDerived: false)
        defer { session.cleanup() }

        #expect(throws: SessionStoreError.self) {
            try session.store.pruneRawStreams(sessionId: session.sessionId)
        }
        #expect(session.store.hasRawStreams(sessionId: session.sessionId))
    }
}
