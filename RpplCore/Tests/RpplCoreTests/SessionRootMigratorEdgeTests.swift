import Foundation
import Testing
@testable import RpplCore

/// The migrator moves user sessions between the local root and iCloud Documents. It must never
/// lose a session or overwrite one with a different id, even when folder names collide.
@Suite("SessionRootMigrator edges", .serialized)
struct SessionRootMigratorEdgeTests {
    private func makeRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Both sessions start at the same minute, so their app-generated folder names collide.
    private struct CollidingSessions {
        let local: SessionFileStore
        let localId: String
        let remote: SessionFileStore
        let remoteId: String
        let roots: [URL]
    }

    private func collidingSessions() throws -> CollidingSessions {
        let localRoot = makeRoot("local")
        let remoteRoot = makeRoot("remote")
        let local = SessionFileStore(rootURL: localRoot)
        let remote = SessionFileStore(rootURL: remoteRoot)
        func manifest() -> SessionManifest {
            SessionManifest(
                testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "w", systemVersion: "26",
                startedAt: Samples.t0
            )
        }
        let a = manifest()
        let b = manifest()
        _ = try local.createSession(manifest: a)
        _ = try remote.createSession(manifest: b)
        try local.appendLocationSamples([Samples.location(0)], sessionId: a.sessionId)
        try remote.appendLocationSamples([Samples.location(1), Samples.location(2)], sessionId: b.sessionId)
        return CollidingSessions(
            local: local, localId: a.sessionId, remote: remote, remoteId: b.sessionId, roots: [localRoot, remoteRoot]
        )
    }

    @Test func localOnlyAndRemoteOnlyAreComplementary() {
        let local: Set<String> = ["a", "b"]
        let remote: Set<String> = ["b", "c"]
        #expect(SessionRootMigrator.localOnlyIDs(local: local, remote: remote) == ["a"])
        #expect(SessionRootMigrator.remoteOnlyIDs(local: local, remote: remote) == ["c"])
    }

    @Test func copyingKeepsBothSessionsWhenFolderNamesCollide() throws {
        let fixture = try collidingSessions()
        defer { fixture.roots.forEach { try? FileManager.default.removeItem(at: $0) } }

        let copied = try SessionRootMigrator.copyMissingPackages(
            from: fixture.remote.rootURL, to: fixture.local.rootURL
        )

        #expect(copied == [fixture.remoteId])
        let ids = Set(try SessionRootMigrator.sessionIDs(in: fixture.local.rootURL))
        #expect(ids == [fixture.localId, fixture.remoteId])
        // Neither session's data was overwritten by the other.
        #expect(try fixture.local.readLocationSamples(sessionId: fixture.localId).count == 1)
        #expect(try fixture.local.readLocationSamples(sessionId: fixture.remoteId).count == 2)
        // The source is untouched.
        #expect(try fixture.remote.readLocationSamples(sessionId: fixture.remoteId).count == 2)
    }

    @Test func copyingTwiceDoesNothingTheSecondTime() throws {
        let fixture = try collidingSessions()
        defer { fixture.roots.forEach { try? FileManager.default.removeItem(at: $0) } }

        _ = try SessionRootMigrator.copyMissingPackages(from: fixture.remote.rootURL, to: fixture.local.rootURL)
        let second = try SessionRootMigrator.copyMissingPackages(from: fixture.remote.rootURL, to: fixture.local.rootURL)

        #expect(second.isEmpty)
        #expect(try SessionRootMigrator.sessionIDs(in: fixture.local.rootURL).count == 2)
    }

    @Test func foldersWithoutAManifestAreNeitherCopiedNorCounted() throws {
        let fixture = try collidingSessions()
        defer { fixture.roots.forEach { try? FileManager.default.removeItem(at: $0) } }
        let stray = fixture.remote.rootURL.appendingPathComponent("not-a-session", isDirectory: true)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: stray.appendingPathComponent("readme.txt"))

        let copied = try SessionRootMigrator.copyMissingPackages(from: fixture.remote.rootURL, to: fixture.local.rootURL)

        #expect(copied == [fixture.remoteId])
        #expect(try SessionRootMigrator.sessionIDs(in: fixture.remote.rootURL) == [fixture.remoteId])
    }

    @Test func movingSendsEverySessionAndEmptiesTheSource() throws {
        let fixture = try collidingSessions()
        defer { fixture.roots.forEach { try? FileManager.default.removeItem(at: $0) } }

        let moved = try SessionRootMigrator.moveAllPackages(from: fixture.remote.rootURL, to: fixture.local.rootURL)

        #expect(moved == [fixture.remoteId])
        #expect(try SessionRootMigrator.sessionIDs(in: fixture.remote.rootURL).isEmpty)
        #expect(Set(try SessionRootMigrator.sessionIDs(in: fixture.local.rootURL)) == [fixture.localId, fixture.remoteId])
        #expect(try fixture.local.readLocationSamples(sessionId: fixture.localId).count == 1)
    }

    @Test func removingAMissingRootIsHarmless() throws {
        try SessionRootMigrator.removeAllPackages(at: makeRoot("missing"))
    }
}
