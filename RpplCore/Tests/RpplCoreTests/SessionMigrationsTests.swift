import Foundation
import Testing
@testable import RpplCore

/// The format is reset to schema v1 and `SessionMigrations.steps` is empty. These tests prove the
/// hook a future schema bump relies on: pending steps run once, in order, and the version is stamped.
@Suite("SessionMigrations", .serialized)
struct SessionMigrationsTests {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func append(_ value: Int) { lock.lock(); values.append(value); lock.unlock() }
        var all: [Int] { lock.lock(); defer { lock.unlock() }; return values }
    }

    @Test func theFormatIsResetToSchemaOneWithNoSteps() {
        #expect(SessionSchema.currentVersion == 1)
        #expect(SessionAnalyzer.version == 1)
        #expect(SessionMigrations.steps.isEmpty)
    }

    @Test func pendingStepsAreFilteredByVersionAndSorted() {
        let steps = [3, 2, 4].map { SessionMigrations.Step(toVersion: $0) { _, _ in } }

        #expect(SessionMigrations.pending(from: 1, to: 3, in: steps).map(\.toVersion) == [2, 3])
        #expect(SessionMigrations.pending(from: 2, to: 3, in: steps).map(\.toVersion) == [3])
        #expect(SessionMigrations.pending(from: 3, to: 3, in: steps).isEmpty)
        #expect(SessionMigrations.pending(from: 1, to: 1, in: steps).isEmpty)
    }

    @Test func aCurrentSessionIsLeftAlone() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }

        #expect(try session.store.migrateIfNeeded(sessionId: session.sessionId) == false)
        #expect(try session.store.readManifest(sessionId: session.sessionId).schemaVersion == 1)
    }

    @Test func aNewerSessionIsNeverDowngraded() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        var manifest = try session.store.readManifest(sessionId: session.sessionId)
        manifest.schemaVersion = 99
        try session.store.writeManifest(manifest)

        #expect(try session.store.migrateIfNeeded(sessionId: session.sessionId) == false)
        #expect(try session.store.readManifest(sessionId: session.sessionId).schemaVersion == 99)
    }

    @Test func pendingStepsRunOnceInOrderAndStampTheVersion() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let log = Log()
        let steps = [
            SessionMigrations.Step(toVersion: 3) { _, _ in log.append(3) },
            SessionMigrations.Step(toVersion: 2) { store, id in
                log.append(2)
                // A step may rewrite the manifest; the version stamp must not undo that.
                var manifest = try store.readManifest(sessionId: id)
                manifest.activityCode = "migrated"
                try store.writeManifest(manifest)
            },
        ]

        let migrated = try session.store.migrateIfNeeded(sessionId: session.sessionId, currentVersion: 3, steps: steps)

        #expect(migrated)
        #expect(log.all == [2, 3])
        let manifest = try session.store.readManifest(sessionId: session.sessionId)
        #expect(manifest.schemaVersion == 3)
        #expect(manifest.activityCode == "migrated")

        #expect(try session.store.migrateIfNeeded(sessionId: session.sessionId, currentVersion: 3, steps: steps) == false)
        #expect(log.all == [2, 3])
    }

    @Test func aFailingStepLeavesTheVersionUnstamped() throws {
        struct StepFailed: Error {}
        let session = try TempSession.make()
        defer { session.cleanup() }
        let steps = [SessionMigrations.Step(toVersion: 2) { _, _ in throw StepFailed() }]

        #expect(throws: StepFailed.self) {
            try session.store.migrateIfNeeded(sessionId: session.sessionId, currentVersion: 2, steps: steps)
        }
        #expect(try session.store.readManifest(sessionId: session.sessionId).schemaVersion == 1)
    }

    @Test func openingASessionRunsTheHook() throws {
        let session = try TempSession.make(endedAt: Samples.time(60), state: .readyToTransfer)
        defer { session.cleanup() }

        // At v1 nothing is pending, so loading must leave the manifest as written.
        let bundle = try SessionLoader.load(store: session.store, sessionId: session.sessionId)
        #expect(bundle.manifest.schemaVersion == SessionSchema.currentVersion)
    }
}
