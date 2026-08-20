import Foundation
import Testing
@testable import RpplCore

@Suite("SessionLoader")
struct SessionLoaderTests {
    @Test func loadBundleIncludesStatsAndByteSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLoaderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "tester-1",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)

        let start = DetectionEvent(
            code: DetectionCodes.inactive,
            reason: "session_start",
            detectorId: "session_start",
            speedMps: nil,
            motionActivity: "stationary"
        )
        try store.appendDetection(start, sessionId: manifest.sessionId)

        let bundle = try SessionLoader.load(store: store, sessionId: manifest.sessionId)
        #expect(bundle.manifest.sessionId == manifest.sessionId)
        #expect(bundle.detections.count == 1)
        #expect(bundle.stats.rideCount == 0)
        #expect(bundle.byteSize >= 0)
    }
}
