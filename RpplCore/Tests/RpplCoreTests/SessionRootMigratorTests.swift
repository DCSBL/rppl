import Foundation
import Testing
@testable import RpplCore

@Suite("RemoteSessionSummary")
struct RemoteSessionSummaryTests {
    @Test func readsManifestAndDerivedView() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = SessionManifest(
            sessionId: "sess-1",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch",
            systemVersion: "26.0",
            startedAt: started,
            endedAt: started.addingTimeInterval(3600)
        )
        _ = try store.createSession(manifest: manifest)
        try store.writeDerivedView(
            DerivedSessionView(
                stats: SessionStats(
                    startedAt: started,
                    endedAt: started.addingTimeInterval(3600),
                    totalDuration: 3600,
                    totalDistanceMeters: 1000,
                    activeEnergyKilocalories: nil,
                    rideCount: 3,
                    ridingDuration: 600,
                    inactiveDuration: 3000,
                    ridingInactiveRatio: 0.2,
                    rides: []
                ),
                cityName: "Utrecht"
            ),
            sessionId: "sess-1"
        )

        let summary = try RemoteSessionSummaryReader.read(
            sessionDirectory: store.sessionDirectory(for: "sess-1")
        )
        #expect(summary.sessionId == "sess-1")
        #expect(summary.cityName == "Utrecht")
        #expect(summary.rideCount == 3)
        #expect(summary.totalDuration == 3600)
        #expect(summary.startedAt == started)
    }

    @Test func fallsBackWhenDerivedMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-bare-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let started = Date(timeIntervalSince1970: 1_700_000_100)
        let manifest = SessionManifest(
            sessionId: "sess-2",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch",
            systemVersion: "26.0",
            startedAt: started,
            endedAt: started.addingTimeInterval(90)
        )
        _ = try store.createSession(manifest: manifest)

        let summary = try RemoteSessionSummaryReader.read(
            sessionDirectory: store.sessionDirectory(for: "sess-2")
        )
        #expect(summary.cityName == nil)
        #expect(summary.rideCount == 0)
        #expect(summary.totalDuration == 90)
    }
}

@Suite("SessionRootMigrator")
struct SessionRootMigratorTests {
    @Test func copyMissingAndRemoteOnly() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("mig-src-\(UUID().uuidString)", isDirectory: true)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("mig-dst-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        let srcStore = SessionFileStore(rootURL: source)
        for id in ["a", "b"] {
            _ = try srcStore.createSession(
                manifest: SessionManifest(
                    sessionId: id,
                    testerId: "t",
                    appVersion: "1",
                    buildNumber: "1",
                    watchModel: "W",
                    systemVersion: "26"
                )
            )
        }
        let dstStore = SessionFileStore(rootURL: dest)
        _ = try dstStore.createSession(
            manifest: SessionManifest(
                sessionId: "a",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "W",
                systemVersion: "26"
            )
        )

        let copied = try SessionRootMigrator.copyMissingPackages(from: source, to: dest)
        #expect(copied == ["b"])
        #expect(Set(try SessionRootMigrator.sessionIDs(in: dest)) == ["a", "b"])

        let remoteOnly = SessionRootMigrator.remoteOnlyIDs(
            local: ["a"],
            remote: ["a", "b", "c"]
        )
        #expect(remoteOnly == ["b", "c"])
    }

    @Test func moveAllAndRemove() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("mov-src-\(UUID().uuidString)", isDirectory: true)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("mov-dst-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        let srcStore = SessionFileStore(rootURL: source)
        _ = try srcStore.createSession(
            manifest: SessionManifest(
                sessionId: "x",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "W",
                systemVersion: "26"
            )
        )

        let moved = try SessionRootMigrator.moveAllPackages(from: source, to: dest)
        #expect(moved == ["x"])
        #expect(try SessionRootMigrator.sessionIDs(in: source).isEmpty)
        #expect(try SessionRootMigrator.sessionIDs(in: dest) == ["x"])

        try SessionRootMigrator.removeAllPackages(at: dest)
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func iCloudSessionsRootPath() {
        let container = URL(fileURLWithPath: "/tmp/fake-ubiquity", isDirectory: true)
        let root = AppConstants.iCloudDocumentsSessionsRoot(containerURL: container)
        #expect(root.path.hasSuffix("Documents/Sessions"))
    }
}
