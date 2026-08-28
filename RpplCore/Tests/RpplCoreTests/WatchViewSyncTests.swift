import Foundation
import Testing
@testable import RpplCore

@Suite("WatchViewSyncCodec")
struct WatchViewSyncCodecTests {
    /// ISO8601 JSON round-trip is second-precision; avoid `Date()` sub-second drift in equality checks.
    private static let sampleStartedAt = Date(timeIntervalSince1970: 1_000_000)

    private func sampleStats(duration: TimeInterval = 120, setCount: Int = 2) -> SessionStats {
        SessionStats(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: duration),
            totalDuration: duration,
            totalDistanceMeters: 500,
            activeEnergyKilocalories: nil,
            setCount: setCount,
            ridingDuration: duration * 0.6,
            inactiveDuration: duration * 0.4,
            ridingInactiveRatio: 0.6,
            sets: []
        )
    }

    private func sampleUpdate(sessionId: String = "abc") -> WatchViewUpdate {
        let manifest = SessionManifest(
            sessionId: sessionId,
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            startedAt: Self.sampleStartedAt,
            transferState: .acknowledged
        )
        let stats = sampleStats()
        let derived = DerivedSessionView(stats: stats, cityName: "Utrecht")
        return WatchViewUpdate(manifest: manifest, derived: derived)
    }

    @Test func viewUpdateRoundTrip() throws {
        let update = sampleUpdate()
        let encoded = try WatchViewSyncCodec.encodeViewUpdate(update)
        let decoded = try #require(try WatchViewSyncCodec.decodeViewUpdate(from: encoded))
        #expect(decoded == update)
    }

    @Test func viewDeleteRoundTrip() {
        let encoded = WatchViewSyncCodec.encodeViewDelete(sessionId: "gone")
        #expect(WatchViewSyncCodec.decodeViewDelete(from: encoded) == "gone")
    }

    @Test func syncRequestRoundTrip() throws {
        let known = [WatchKnownSession(sessionId: "a", analyzerVersion: 2)]
        let encoded = try WatchViewSyncCodec.encodeSyncRequest(known: known)
        let decoded = try #require(try WatchViewSyncCodec.decodeSyncRequest(from: encoded))
        #expect(decoded == known)
    }

    @Test func syncReplyRoundTrip() throws {
        let reply = WatchViewSyncReply(
            updates: [sampleUpdate(sessionId: "one")],
            deletes: ["two"]
        )
        let encoded = try WatchViewSyncCodec.encodeSyncReply(reply)
        let decoded = try #require(try WatchViewSyncCodec.decodeSyncReply(from: encoded))
        #expect(decoded.updates == reply.updates)
        #expect(decoded.deletes == reply.deletes)
    }
}

@Suite("WatchViewSyncDiff")
struct WatchViewSyncDiffTests {
    private func sampleStats(duration: TimeInterval = 1) -> SessionStats {
        SessionStats(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: duration),
            totalDuration: duration,
            totalDistanceMeters: 0,
            activeEnergyKilocalories: nil,
            setCount: 0,
            ridingDuration: 0,
            inactiveDuration: duration,
            ridingInactiveRatio: 0,
            sets: []
        )
    }

    @Test func replySkipsFreshAndAddsDeletes() {
        let phone = WatchViewUpdate(
            manifest: SessionManifest(
                sessionId: "keep",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "w",
                systemVersion: "26",
                transferState: .acknowledged
            ),
            derived: DerivedSessionView(analyzerVersion: 2, stats: sampleStats(duration: 1))
        )
        let known = [
            WatchKnownSession(sessionId: "keep", analyzerVersion: 2),
            WatchKnownSession(sessionId: "gone", analyzerVersion: 2),
        ]
        let reply = WatchViewSyncDiff.reply(knownOnWatch: known, phoneUpdates: [phone])
        #expect(reply.updates.isEmpty)
        #expect(reply.deletes == ["gone"])
    }

    @Test func replyIncludesStaleAnalyzer() {
        let phone = WatchViewUpdate(
            manifest: SessionManifest(
                sessionId: "stale",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "w",
                systemVersion: "26",
                transferState: .acknowledged
            ),
            derived: DerivedSessionView(analyzerVersion: 3, stats: sampleStats(duration: 1))
        )
        let known = [WatchKnownSession(sessionId: "stale", analyzerVersion: 2)]
        let reply = WatchViewSyncDiff.reply(knownOnWatch: known, phoneUpdates: [phone])
        #expect(reply.updates == [phone])
        #expect(reply.deletes.isEmpty)
    }
}

@Suite("SessionFileStore distilled")
struct SessionFileStoreDistilledTests {
    private func sampleStats(duration: TimeInterval) -> SessionStats {
        SessionStats(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: duration),
            totalDuration: duration,
            totalDistanceMeters: 0,
            activeEnergyKilocalories: nil,
            setCount: 0,
            ridingDuration: 0,
            inactiveDuration: duration,
            ridingInactiveRatio: 0,
            sets: []
        )
    }

    @Test func pruneRawStreamsKeepsManifestAndDerived() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        var manifest = SessionManifest(
            sessionId: "prune-me",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            transferState: .acknowledged
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendDetection(
            DetectionEvent(code: DetectionCodes.inactive, reason: "t", detectorId: "t"),
            sessionId: manifest.sessionId
        )
        try store.appendLocationSamples(
            [
                LocationSample(
                    timestamp: Date(),
                    latitude: 1,
                    longitude: 2,
                    horizontalAccuracy: 5
                ),
            ],
            sessionId: manifest.sessionId
        )
        try store.writeDerivedView(
            DerivedSessionView(stats: sampleStats(duration: 10)),
            sessionId: manifest.sessionId
        )

        #expect(store.hasRawStreams(sessionId: manifest.sessionId))
        try store.pruneRawStreams(sessionId: manifest.sessionId)
        #expect(store.hasRawStreams(sessionId: manifest.sessionId) == false)
        #expect(try store.readManifest(sessionId: manifest.sessionId).sessionId == manifest.sessionId)
        #expect(try store.readDerivedView(sessionId: manifest.sessionId) != nil)
    }

    @Test func pruneRawStreamsIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-idem-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "idem",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            transferState: .acknowledged
        )
        _ = try store.createSession(manifest: manifest)
        try store.writeDerivedView(
            DerivedSessionView(stats: sampleStats(duration: 1)),
            sessionId: manifest.sessionId
        )
        try store.pruneRawStreams(sessionId: manifest.sessionId)
        try store.pruneRawStreams(sessionId: manifest.sessionId)
    }

    @Test func applyDistilledViewPrunesWhenAcknowledged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("apply-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "apply",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            transferState: .acknowledged
        )
        _ = try store.createSession(manifest: manifest)
        try store.appendLocationSamples(
            [
                LocationSample(
                    timestamp: Date(),
                    latitude: 1,
                    longitude: 2,
                    horizontalAccuracy: 5
                ),
            ],
            sessionId: manifest.sessionId
        )
        let update = WatchViewUpdate(
            manifest: manifest,
            derived: DerivedSessionView(stats: sampleStats(duration: 99), cityName: "Phone")
        )
        try store.applyDistilledView(update)
        #expect(store.hasRawStreams(sessionId: manifest.sessionId) == false)
        #expect(try store.readDerivedView(sessionId: manifest.sessionId)?.cityName == "Phone")
    }

    @Test func loadStoredSummaryDoesNotRebuild() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stored-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "stored",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            transferState: .acknowledged
        )
        _ = try store.createSession(manifest: manifest)
        try store.writeDerivedView(
            DerivedSessionView(analyzerVersion: 1, stats: sampleStats(duration: 42)),
            sessionId: manifest.sessionId
        )
        try store.pruneRawStreams(sessionId: manifest.sessionId)

        let summary = try SessionLoader.loadStoredSummary(store: store, sessionId: manifest.sessionId)
        #expect(summary.stats.totalDuration == 42)
    }
}
