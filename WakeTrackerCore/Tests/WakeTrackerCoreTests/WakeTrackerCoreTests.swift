import Foundation
import Testing
@testable import WakeTrackerCore

@Suite("LabelCodes")
struct LabelCodesTests {
    @Test func cyclesInExpectedOrder() {
        #expect(LabelCodes.next(after: LabelCodes.waiting) == LabelCodes.riding)
        #expect(LabelCodes.next(after: LabelCodes.riding) == LabelCodes.swimming)
        #expect(LabelCodes.next(after: LabelCodes.swimming) == LabelCodes.walking)
        #expect(LabelCodes.next(after: LabelCodes.walking) == LabelCodes.waiting)
    }

    @Test func unknownCodeRestartsCycle() {
        #expect(LabelCodes.next(after: "dockStartJump") == LabelCodes.waiting)
    }

    @Test func fullCycleReturnsToStart() {
        var code = LabelCodes.waiting
        for _ in 0..<LabelCodes.actionButtonCycle.count {
            code = LabelCodes.next(after: code)
        }
        #expect(code == LabelCodes.waiting)
    }

    @Test func multiStepFromWaiting() {
        let riding = LabelCodes.next(after: LabelCodes.waiting)
        let swimming = LabelCodes.next(after: riding)
        let walking = LabelCodes.next(after: swimming)
        #expect([riding, swimming, walking] == [
            LabelCodes.riding,
            LabelCodes.swimming,
            LabelCodes.walking,
        ])
    }
}

@Suite("SessionFileStore")
struct SessionFileStoreTests {
    @Test func createsManifestAndRoundTripsLabels() throws {
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

        let event = LabelEvent(
            code: LabelCodes.waiting,
            gps: GPSSnapshot(
                latitude: 52.1,
                longitude: 5.1,
                horizontalAccuracy: 5,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            waterSubmersionState: "notSubmerged",
            waterTemperatureCelsius: 18.5,
            motionActivity: "stationary"
        )
        try store.appendLabel(event, sessionId: manifest.sessionId)

        let loaded = try store.readManifest(sessionId: manifest.sessionId)
        #expect(loaded.testerId == "tester-1")
        #expect(loaded.schemaVersion == SessionSchema.currentVersion)

        let labels = try store.readLabels(sessionId: manifest.sessionId)
        #expect(labels.count == 1)
        #expect(labels[0].code == LabelCodes.waiting)
        #expect(labels[0].waterTemperatureCelsius == 18.5)
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
        var manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try watchStore.createSession(manifest: manifest)
        try watchStore.appendLabel(LabelEvent(code: LabelCodes.riding), sessionId: manifest.sessionId)
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
        #expect(try phoneStore.readLabels(sessionId: manifest.sessionId).count == 1)
        #expect(try phoneStore.readLocationSamples(sessionId: manifest.sessionId).count == 1)
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
