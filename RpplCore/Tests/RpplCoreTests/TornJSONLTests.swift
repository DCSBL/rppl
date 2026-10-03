import Foundation
import Testing
@testable import RpplCore

@Suite("Tolerant JSONL", .serialized)
struct TornJSONLTests {
    private struct Fixture {
        let store: SessionFileStore
        let root: URL
        let sessionId: String
    }

    private func makeStore() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "Watch7,1", systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)
        return Fixture(store: store, root: root, sessionId: manifest.sessionId)
    }

    private func event(_ reason: String) -> DetectionEvent {
        DetectionEvent(code: DetectionCodes.inactive, reason: reason, detectorId: reason)
    }

    private func location(_ offset: TimeInterval) -> LocationSample {
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000 + offset),
            latitude: 52.0, longitude: 4.0, horizontalAccuracy: 5, speed: 1
        )
    }

    private func append(_ bytes: [UInt8], to name: String, store: SessionFileStore, sessionId: String) throws {
        let url = try store.sessionDirectory(for: sessionId).appendingPathComponent(name)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(bytes))
    }

    @Test func tornLastLineKeepsValidLines() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let root = fixture.root
        let id = fixture.sessionId
        defer { try? FileManager.default.removeItem(at: root) }
        try store.appendDetection(event("a"), sessionId: id)
        try store.appendDetection(event("b"), sessionId: id)
        try append(Array(#"{"code":"rid"#.utf8), to: "detections.jsonl", store: store, sessionId: id)

        let read = try store.readDetections(sessionId: id)
        #expect(read.map(\.reason) == ["a", "b"])
    }

    @Test func appendAfterTornLineIsReadable() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let root = fixture.root
        let id = fixture.sessionId
        defer { try? FileManager.default.removeItem(at: root) }
        try store.appendDetection(event("a"), sessionId: id)
        try append(Array(#"{"code":"rid"#.utf8), to: "detections.jsonl", store: store, sessionId: id)
        try store.appendDetection(event("b"), sessionId: id)

        let read = try store.readDetections(sessionId: id)
        #expect(read.map(\.reason) == ["a", "b"])
    }

    @Test func invalidUTF8ByteOnlyCostsItsLine() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let root = fixture.root
        let id = fixture.sessionId
        defer { try? FileManager.default.removeItem(at: root) }
        try store.appendDetection(event("a"), sessionId: id)
        try append([0xFF, 0xFE, 0x0A], to: "detections.jsonl", store: store, sessionId: id)
        try store.appendDetection(event("b"), sessionId: id)

        #expect(try store.readDetections(sessionId: id).map(\.reason) == ["a", "b"])
    }

    @Test func finalizeOrphanedRecordingSurvivesTornFiles() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let root = fixture.root
        let id = fixture.sessionId
        defer { try? FileManager.default.removeItem(at: root) }
        try store.appendDetection(event("a"), sessionId: id)
        try store.appendLocationSamples([location(0), location(1)], sessionId: id)
        try append(Array(#"{"latitude":52.0"#.utf8), to: "detections.jsonl", store: store, sessionId: id)
        try append(Array(#"{"latitude":52.0"#.utf8), to: "location-000.jsonl", store: store, sessionId: id)

        #expect(try store.finalizeOrphanedRecording(sessionId: id))
        #expect(try store.readManifest(sessionId: id).transferState == .readyToTransfer)
        #expect(try store.readLocationSamples(sessionId: id).count == 2)
    }
}
