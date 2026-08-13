import Foundation
import Testing
@testable import WakeTrackerCore

@Suite("DetectionCodes")
struct DetectionCodesTests {
    @Test func confidentCodes() {
        #expect(DetectionCodes.isConfident(DetectionCodes.riding))
        #expect(DetectionCodes.isConfident(DetectionCodes.paused))
        #expect(!DetectionCodes.isConfident(DetectionCodes.unsure))
        #expect(!DetectionCodes.isConfident("waiting"))
    }
}

@Suite("SessionFileStore")
struct SessionFileStoreTests {
    @Test func createsManifestAndRoundTripsDetections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WakeTrackerCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "tester-1",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)

        let event = DetectionEvent(
            code: DetectionCodes.paused,
            reason: "session_start",
            detectorId: "session_start",
            speedMps: nil,
            motionActivity: "stationary"
        )
        try store.appendDetection(event, sessionId: manifest.sessionId)

        let loaded = try store.readManifest(sessionId: manifest.sessionId)
        #expect(loaded.testerId == "tester-1")
        #expect(loaded.schemaVersion == SessionSchema.currentVersion)

        let detections = try store.readDetections(sessionId: manifest.sessionId)
        #expect(detections.count == 1)
        #expect(detections[0].code == DetectionCodes.paused)
        #expect(detections[0].detectorId == "session_start")
    }

    @Test func transferPackageRoundTripPreservesSamples() throws {
        let watchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(UUID().uuidString)", isDirectory: true)
        let phoneRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("phone-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: watchRoot)
            try? FileManager.default.removeItem(at: phoneRoot)
        }

        let watchStore = SessionFileStore(rootURL: watchRoot)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try watchStore.createSession(manifest: manifest)
        try watchStore.appendDetection(
            DetectionEvent(
                code: DetectionCodes.riding,
                reason: "ride_enter",
                detectorId: "ride_enter"
            ),
            sessionId: manifest.sessionId
        )
        try watchStore.appendLocationSamples([
            LocationSample(
                timestamp: Date(timeIntervalSince1970: 10),
                latitude: 1,
                longitude: 2,
                horizontalAccuracy: 3,
                speed: 4
            )
        ], sessionId: manifest.sessionId)
        try watchStore.markReadyToTransfer(sessionId: manifest.sessionId)

        let package = try watchStore.buildTransferPackage(sessionId: manifest.sessionId)
        try watchStore.importTransferPackage(package, intoPhoneStore: phoneRoot)

        let phoneStore = SessionFileStore(rootURL: phoneRoot)
        let phoneManifest = try phoneStore.readManifest(sessionId: manifest.sessionId)
        #expect(phoneManifest.transferState == .acknowledged)
        #expect(try phoneStore.readDetections(sessionId: manifest.sessionId).count == 1)
        #expect(try phoneStore.readLocationSamples(sessionId: manifest.sessionId).count == 1)
    }

    @Test func migratesLegacyAssumptionsFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)

        let assumptionsURL = store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("assumptions.jsonl")
        let legacy =
            #"{"code":"riding","id":"legacy-1","reason":"ride_start","timestamp":"2024-01-01T00:00:00Z"}"#
            + "\n"
        try Data(legacy.utf8).write(to: assumptionsURL)
        // Empty detections from createSession — migrate should fill from assumptions.
        let detectionsURL = store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("detections.jsonl")
        try Data().write(to: detectionsURL)

        let detections = try store.readDetections(sessionId: manifest.sessionId)
        #expect(detections.count == 1)
        #expect(detections[0].code == "riding")
        #expect(detections[0].id == "legacy-1")
        #expect(!FileManager.default.fileExists(atPath: assumptionsURL.path))
    }

    @Test func legacyTransferAssumptionsBecomeDetections() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = Data(
            #"""
            {
              "manifest": {
                "schemaVersion": 2,
                "sessionId": "s1",
                "testerId": "t",
                "appVersion": "1.0",
                "buildNumber": "1",
                "watchModel": "Ultra2",
                "systemVersion": "26.0",
                "startedAt": "2024-01-01T00:00:00Z",
                "transferState": "acknowledged"
              },
              "labels": [{"code":"waiting","id":"l1","timestamp":"2024-01-01T00:00:00Z"}],
              "assumptions": [{"code":"riding","id":"a1","reason":"ride_start","timestamp":"2024-01-01T00:00:01Z"}],
              "locations": [],
              "health": []
            }
            """#.utf8
        )
        let package = try decoder.decode(SessionTransferPackage.self, from: json)
        #expect(package.detections.count == 1)
        #expect(package.detections[0].code == "riding")
        #expect(package.detections[0].id == "a1")
    }

    @Test func failedTransferDoesNotDropReadySessions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xfer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)
        try store.markReadyToTransfer(sessionId: manifest.sessionId)
        try store.markTransferring(sessionId: manifest.sessionId)

        let pending = try store.sessionsNeedingTransfer()
        #expect(pending.map(\.sessionId) == [manifest.sessionId])

        // Simulate failure: leave as transferring / ready — still present on disk
        let stillThere = try store.readManifest(sessionId: manifest.sessionId)
        #expect(stillThere.transferState == .transferring)
    }

    @Test func unreadableSiblingDoesNotHidePendingTransfer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orphan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let ready = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: ready)
        try store.markReadyToTransfer(sessionId: ready.sessionId)

        // Empty dormant folder (no manifest.json) — must not abort the pending list.
        let emptyDir = root.appendingPathComponent("zzz-empty-dormant", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        // Corrupt manifest sibling — same: skip, do not throw away ready sessions.
        let corruptDir = root.appendingPathComponent("aaa-corrupt-dormant", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(
            to: corruptDir.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        let pending = try store.sessionsNeedingTransfer()
        #expect(pending.map(\.sessionId) == [ready.sessionId])
        #expect(pending.first?.transferState == .readyToTransfer)

        let readable = try store.listReadableManifests()
        #expect(readable.map(\.sessionId) == [ready.sessionId])
    }

    @Test func sessionStoreErrorHasReadableDescription() {
        #expect(
            SessionStoreError.invalidManifest.localizedDescription == "Invalid session manifest"
        )
        #expect(
            SessionStoreError.sessionNotFound("abc").localizedDescription
                == "Session not found: abc"
        )
        #expect(
            SessionStoreError.ioFailure("disk full").localizedDescription == "disk full"
        )
    }

    @Test func emptyStoreHasNoPendingTransfers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        #expect(try store.sessionsNeedingTransfer().isEmpty)
        #expect(try store.listSessionIDs().isEmpty)
    }

    @Test func acknowledgedSessionLeavesPendingEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ack-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)
        try store.markReadyToTransfer(sessionId: manifest.sessionId)
        try store.markAcknowledged(sessionId: manifest.sessionId)
        #expect(try store.sessionsNeedingTransfer().isEmpty)
    }

    @Test func recordingSessionNotPending() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)
        #expect(try store.sessionsNeedingTransfer().isEmpty)
    }

    @Test func listSessionIDsSorted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        for id in ["b-session", "a-session", "c-session"] {
            _ = try store.createSession(
                manifest: SessionManifest(
                    sessionId: id,
                    testerId: "t",
                    appVersion: "1.0",
                    buildNumber: "1",
                    watchModel: "Ultra2",
                    systemVersion: "26.0"
                )
            )
        }
        #expect(try store.listSessionIDs() == ["a-session", "b-session", "c-session"])
    }

    @Test func sessionByteSizeGrowsWithAppends() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("size-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)

        let afterCreate = try store.sessionByteSize(sessionId: manifest.sessionId)
        #expect(afterCreate > 0)
        #expect(try store.totalStoredByteSize() == afterCreate)

        try store.appendDetection(
            DetectionEvent(code: DetectionCodes.riding, reason: "t", detectorId: "t"),
            sessionId: manifest.sessionId
        )
        try store.appendLocationSamples([
            LocationSample(
                timestamp: Date(timeIntervalSince1970: 10),
                latitude: 1,
                longitude: 2,
                horizontalAccuracy: 3,
                speed: 4
            )
        ], sessionId: manifest.sessionId)

        let afterAppend = try store.sessionByteSize(sessionId: manifest.sessionId)
        #expect(afterAppend > afterCreate)
        #expect(try store.totalStoredByteSize() == afterAppend)
    }

    @Test func totalStoredByteSizeSumsSessions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("totalsize-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        var sizes: [Int64] = []
        for id in ["s1", "s2"] {
            try store.createSession(
                manifest: SessionManifest(
                    sessionId: id,
                    testerId: "t",
                    appVersion: "1.0",
                    buildNumber: "1",
                    watchModel: "Ultra2",
                    systemVersion: "26.0"
                )
            )
            try store.appendDetection(
                DetectionEvent(code: DetectionCodes.paused, reason: "t", detectorId: "t"),
                sessionId: id
            )
            sizes.append(try store.sessionByteSize(sessionId: id))
        }
        #expect(try store.totalStoredByteSize() == sizes.reduce(0, +))
    }

    @Test func sessionByteSizeThrowsWhenMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        #expect(throws: SessionStoreError.sessionNotFound("nope")) {
            try store.sessionByteSize(sessionId: "nope")
        }
    }

    @Test func deleteSessionRemovesPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "to-delete",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(code: DetectionCodes.paused, reason: "t", detectorId: "t"),
            sessionId: manifest.sessionId
        )
        #expect(try store.listSessionIDs() == ["to-delete"])

        try store.deleteSession(sessionId: manifest.sessionId)
        #expect(try store.listSessionIDs().isEmpty)
        #expect(throws: SessionStoreError.sessionNotFound("to-delete")) {
            try store.readManifest(sessionId: "to-delete")
        }
    }

    @Test func deleteSessionThrowsWhenMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        #expect(throws: SessionStoreError.sessionNotFound("nope")) {
            try store.deleteSession(sessionId: "nope")
        }
    }

    @Test func byteSizeFormatNonEmpty() {
        #expect(!ByteSizeFormat.string(0).isEmpty)
        #expect(!ByteSizeFormat.string(1_500).isEmpty)
        #expect(!ByteSizeFormat.string(2_500_000).isEmpty)
    }

    @Test func readLocationSamplesHonorsTaskCancellation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)

        let samples = (0..<4_000).map { index in
            LocationSample(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                latitude: Double(index) * 0.0001,
                longitude: Double(index) * 0.0001,
                horizontalAccuracy: 5
            )
        }
        try store.appendLocationSamples(samples, sessionId: manifest.sessionId)

        let reader = Task {
            try store.readLocationSamples(sessionId: manifest.sessionId)
        }
        // Cancel before the cooperative checkpoints can finish the whole file.
        reader.cancel()
        do {
            _ = try await reader.value
            Issue.record("Expected CancellationError from cancelled JSONL read")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testerIdentityPersistsInDefaults() {
        let suite = "WakeTrackerCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TesterIdentity.resolve(store: defaults)
        let second = TesterIdentity.resolve(store: defaults)
        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }
}
