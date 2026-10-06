import Foundation
import Testing
@testable import RpplCore

/// The phone acks whatever package arrives and the Watch then prunes its raw streams. A package
/// built with a stream silently missing would turn a read error into permanent data loss, so
/// the Watch must fail the transfer (and keep its files) instead.
@Suite("Transfer package completeness", .serialized)
struct TransferPackageCompletenessTests {
    private static let streams = [
        "detections.jsonl",
        "location-000.jsonl",
        "health-000.jsonl",
        "water-000.jsonl",
        "battery-000.jsonl",
        "altitude-000.jsonl",
        "motion-000.jsonl.zlib"
    ]

    private func recordedSession() throws -> TempSession {
        let session = try TempSession.make(endedAt: Samples.time(60), state: .readyToTransfer)
        let id = session.sessionId
        try session.store.appendDetection(Samples.detection(DetectionCodes.inactive, second: 0), sessionId: id)
        _ = SessionFlushWriter.write(
            locations: (0..<10).map { Samples.location($0) },
            health: (0..<10).map { Samples.health($0) },
            water: [Samples.water(0)],
            battery: [Samples.battery(0)],
            altitude: (0..<10).map { Samples.altitude($0) },
            store: session.store,
            sessionId: id
        )
        try session.store.appendMotionSamples((0..<10).map { Samples.motion($0) }, sessionId: id)
        return session
    }

    private func setPermissions(_ mode: Int, _ name: String, in session: TempSession) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: session.file(name).path)
    }

    @Test func aCompleteSessionBuildsAFullPackage() throws {
        let session = try recordedSession()
        defer { session.cleanup() }

        let package = try session.store.buildTransferPackage(sessionId: session.sessionId)

        #expect(package.detections.count == 1)
        #expect(package.locations.count == 10)
        #expect(package.health.count == 10)
        #expect(package.water.count == 1)
        #expect(package.battery.count == 1)
        #expect(package.altitude.count == 10)
        #expect(package.motionFramesZlib?.isEmpty == false)
    }

    @Test(arguments: TransferPackageCompletenessTests.streams)
    func anUnreadableStreamFailsTheTransferInsteadOfShippingItEmpty(name: String) throws {
        let session = try recordedSession()
        defer {
            try? setPermissions(0o644, name, in: session)
            session.cleanup()
        }
        try setPermissions(0o000, name, in: session)

        #expect(throws: (any Error).self) {
            try session.store.buildTransferPackage(sessionId: session.sessionId)
        }
    }

    @Test func aFailedBuildLeavesTheSessionReadyToRetry() throws {
        let session = try recordedSession()
        defer {
            try? setPermissions(0o644, "location-000.jsonl", in: session)
            session.cleanup()
        }
        try setPermissions(0o000, "location-000.jsonl", in: session)
        let outbox = session.root.appendingPathComponent("outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try session.store.zipSessionForTransfer(sessionId: session.sessionId, to: outbox)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: outbox.path).isEmpty)
        #expect(try session.store.readManifest(sessionId: session.sessionId).transferState == .readyToTransfer)
        #expect(session.store.hasRawStreams(sessionId: session.sessionId))
    }

    @Test func aStreamThatWasNeverWrittenIsNotAnError() throws {
        // Water only records while submerged, battery only on a Watch that reports it.
        let session = try TempSession.make(endedAt: Samples.time(60), state: .readyToTransfer)
        defer { session.cleanup() }
        _ = SessionFlushWriter.write(
            locations: [Samples.location(0)], health: [], water: [], battery: [],
            store: session.store, sessionId: session.sessionId
        )

        let package = try session.store.buildTransferPackage(sessionId: session.sessionId)

        #expect(package.locations.count == 1)
        #expect(package.water.isEmpty)
        #expect(package.battery.isEmpty)
        #expect(package.motionFramesZlib == nil)
    }
}
