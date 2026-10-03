import Foundation
import Testing
@testable import RpplCore

/// What the phone does with a package from the Watch: bounds on size and counts, what an existing
/// copy is replaced by, and the WatchConnectivity keys both apps must agree on.
@Suite("Session import boundaries", .serialized)
struct SessionImportBoundaryTests {
    private func phoneRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-phone-\(UUID().uuidString)", isDirectory: true)
    }

    private func package(
        for session: TempSession,
        detections: [DetectionEvent] = [],
        locations: [LocationSample] = []
    ) throws -> SessionTransferPackage {
        SessionTransferPackage(
            manifest: try session.store.readManifest(sessionId: session.sessionId),
            detections: detections,
            locations: locations,
            motion: [],
            motionFramesZlib: nil,
            health: [],
            water: [],
            battery: [],
            derived: nil
        )
    }

    // MARK: limits

    @Test func aFileExactlyAtTheLimitIsAccepted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("limit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("package.json")
        try Data(repeating: 0x20, count: 1024).write(to: url)

        #expect(try SessionImportLimits.readBoundedFile(at: url, maxBytes: 1024).count == 1024)
        #expect(throws: SessionStoreError.importTooLarge(1024)) {
            _ = try SessionImportLimits.readBoundedFile(at: url, maxBytes: 1023)
        }
    }

    @Test func anArrayExactlyAtTheLimitIsAccepted() throws {
        try SessionImportLimits.validateArrayCount(Array(repeating: 0, count: 5), limit: 5, label: "x")
        #expect(throws: SessionStoreError.importLimitExceeded("x count 6 > 5")) {
            try SessionImportLimits.validateArrayCount(Array(repeating: 0, count: 6), limit: 5, label: "x")
        }
    }

    @Test func aHeatmapTrackWithTooManyPointsNamesTheTrack() {
        let ok = Array(repeating: MapCoordinate(latitude: 1, longitude: 2), count: SessionImportLimits.maxHeatmapPointsPerTrack)
        let tooMany = ok + [MapCoordinate(latitude: 1, longitude: 2)]
        #expect(throws: Never.self) { try SessionImportLimits.validateHeatmapTracks([ok]) }
        #expect(throws: SessionStoreError.self) { try SessionImportLimits.validateHeatmapTracks([ok, tooMany]) }
    }

    @Test func garbageIsNotATransferPackage() {
        #expect(throws: DecodingError.self) {
            _ = try SessionImportLimits.decodeTransferPackage(from: Data("not json".utf8))
        }
    }

    @Test func anOverLimitPackageIsRefusedAndLeavesNothingOnThePhone() throws {
        let session = try TempSession.make()
        let root = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: root) }
        let tooMany = (0...SessionImportLimits.maxDetections).map { Samples.detection(DetectionCodes.inactive, second: $0 % 100) }
        let oversized = try package(for: session, detections: tooMany)

        #expect(throws: SessionStoreError.self) {
            try session.store.importTransferPackage(oversized, intoPhoneStore: root)
        }
        #expect(try SessionFileStore(rootURL: root).listSessionIDs().isEmpty)
    }

    // MARK: replacing an existing copy

    @Test func anEmptyPackageNeverReplacesAPhoneCopyThatHasOnlyLocations() throws {
        let session = try TempSession.make()
        let root = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: root) }
        let id = session.sessionId
        try session.store.importTransferPackage(
            package(for: session, locations: (0..<20).map { Samples.location($0) }),
            intoPhoneStore: root
        )

        // A pruned Watch session re-sent by mistake carries nothing.
        try session.store.importTransferPackage(package(for: session), intoPhoneStore: root)

        #expect(try SessionFileStore(rootURL: root).readLocationSamples(sessionId: id).count == 20)
    }

    @Test func aNonEmptyPackageReplacesTheWholeCopyInsteadOfAppending() throws {
        let session = try TempSession.make()
        let root = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: root) }
        let id = session.sessionId
        try session.store.importTransferPackage(
            package(for: session, locations: (0..<20).map { Samples.location($0) }),
            intoPhoneStore: root
        )

        try session.store.importTransferPackage(
            package(for: session, locations: (100..<105).map { Samples.location($0) }),
            intoPhoneStore: root
        )

        let stored = try SessionFileStore(rootURL: root).readLocationSamples(sessionId: id)
        #expect(stored.map(\.timestamp) == (100..<105).map { Samples.time($0) })
    }

    @Test func aPathTraversingSessionIdIsRefusedBeforeAnythingIsWritten() throws {
        let session = try TempSession.make()
        let root = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: root) }
        var evil = try package(for: session, locations: [Samples.location(0)])
        evil.manifest.sessionId = "../../escape"

        #expect(throws: SessionStoreError.self) {
            try session.store.importTransferPackage(evil, intoPhoneStore: root)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    // MARK: wire contract

    /// Watch and phone builds are updated separately; renaming one of these keys silently breaks
    /// ack, nack or logbook sync between a new and an old build.
    @Test func watchConnectivityKeysAreStable() {
        #expect(AppConstants.wcSessionFileMetaSessionID == "sessionId")
        #expect(AppConstants.wcAckMessageKey == "ackSessionId")
        #expect(AppConstants.wcNackMessageKey == "nackSessionId")
        #expect(AppConstants.wcNackReasonKey == "nackReason")
        #expect(AppConstants.wcMessageTypeKey == "rpplMessageType")
        #expect(AppConstants.wcViewUpdateSessionIdKey == "sessionId")
        #expect(AppConstants.wcViewUpdateManifestKey == "manifestJSON")
        #expect(AppConstants.wcViewUpdateDerivedKey == "derivedJSON")
        #expect(AppConstants.wcViewDeleteSessionIdKey == "sessionId")
        #expect(AppConstants.wcSyncKnownSessionsKey == "knownSessions")
        #expect(AppConstants.wcSyncDeletesKey == "deletes")
        #expect(AppConstants.wcSyncUpdatesKey == "updates")
    }

    @Test func sessionsLiveInASessionsFolderUnderTheBase() {
        let base = URL(fileURLWithPath: "/tmp/base", isDirectory: true)
        #expect(AppConstants.sessionsRoot(in: base).path == "/tmp/base/Sessions")
        #expect(AppConstants.iCloudDocumentsSessionsRoot(containerURL: base).path == "/tmp/base/Documents/Sessions")
    }
}
