import Foundation
import Testing
@testable import RpplCore

/// Fails the last write of an import (the `derived/` folder, written after every raw stream), like
/// a disk that fills up part-way. Everything before it has already been written by then.
private final class FailingDerivedFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if url.lastPathComponent == "derived" {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

@Suite("Atomic session import", .serialized)
struct SessionImportAtomicTests {
    private func phoneRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-phone-\(UUID().uuidString)", isDirectory: true)
    }

    private func package(for session: TempSession, locations: Int) throws -> SessionTransferPackage {
        try session.store.appendDetection(Samples.detection(DetectionCodes.riding, second: 1), sessionId: session.sessionId)
        try session.store.appendLocationSamples((0..<locations).map { Samples.location($0) }, sessionId: session.sessionId)
        try session.store.markReadyToTransfer(sessionId: session.sessionId, endedAt: Samples.time(locations))
        return try session.store.buildTransferPackage(sessionId: session.sessionId)
    }

    @Test func aFailedSwapLeavesAnExistingCopyUntouched() throws {
        let session = try TempSession.make()
        let phone = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phone) }
        let first = try package(for: session, locations: 5)
        try session.store.importTransferPackage(first, intoPhoneStore: phone)

        // The same session arrives again with more data, but the import fails part-way.
        try session.store.appendLocationSamples((5..<20).map { Samples.location($0) }, sessionId: session.sessionId)
        let second = try session.store.buildTransferPackage(sessionId: session.sessionId)
        let failing = SessionFileStore(rootURL: session.root, fileManager: FailingDerivedFileManager())
        #expect(throws: CocoaError.self) {
            try failing.importTransferPackage(second, intoPhoneStore: phone)
        }

        let phoneStore = SessionFileStore(rootURL: phone)
        #expect(try phoneStore.readLocationSamples(sessionId: session.sessionId).count == 5)
        #expect(try phoneStore.readManifest(sessionId: session.sessionId).transferState == .acknowledged)
        let folders = try FileManager.default.contentsOfDirectory(atPath: phone.path)
        #expect(folders.count == 1)
    }

    @Test func aFailedFirstImportLeavesNoPackageBehind() throws {
        let session = try TempSession.make()
        let phone = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phone) }
        let incoming = try package(for: session, locations: 5)
        let failing = SessionFileStore(rootURL: session.root, fileManager: FailingDerivedFileManager())

        #expect(throws: CocoaError.self) {
            try failing.importTransferPackage(incoming, intoPhoneStore: phone)
        }

        #expect(try SessionPackageLocator.sessionIDs(in: phone).isEmpty)
    }

    @Test func aReplacedImportKeepsTheExistingFolderName() throws {
        let session = try TempSession.make()
        let phone = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phone) }
        let first = try package(for: session, locations: 5)
        try session.store.importTransferPackage(first, intoPhoneStore: phone)
        let before = try SessionPackageLocator.directory(for: session.sessionId, in: phone)

        try session.store.appendLocationSamples((5..<9).map { Samples.location($0) }, sessionId: session.sessionId)
        try session.store.importTransferPackage(
            session.store.buildTransferPackage(sessionId: session.sessionId),
            intoPhoneStore: phone
        )

        let after = try SessionPackageLocator.directory(for: session.sessionId, in: phone)
        #expect(after.lastPathComponent == before.lastPathComponent)
        #expect(try SessionFileStore(rootURL: phone).readLocationSamples(sessionId: session.sessionId).count == 9)
    }

    @Test func importedMotionWithADamagedTailKeepsTheGoodFramesAndNotesTheLoss() throws {
        let session = try TempSession.make()
        let phone = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phone) }
        var incoming = try package(for: session, locations: 5)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var jsonl = Data()
        for second in 0..<5 {
            jsonl.append(try encoder.encode(Samples.motion(second)))
            jsonl.append(0x0A)
        }
        let good = try CompressedJSONLFrames.makeFrame(jsonlUTF8: jsonl)
        incoming.motionFramesZlib = good + good.prefix(7)

        try session.store.importTransferPackage(incoming, intoPhoneStore: phone)

        let phoneStore = SessionFileStore(rootURL: phone)
        #expect(try phoneStore.readMotionSamples(sessionId: session.sessionId).count == 5)
        let manifest = try phoneStore.readManifest(sessionId: session.sessionId)
        #expect(manifest.motionStoppedReason == MotionRecordingPolicy.Reason.importLimit)
        #expect(try phoneStore.readLocationSamples(sessionId: session.sessionId).count == 5)
    }

    @Test func cleanMotionDoesNotSetAStopReason() throws {
        let session = try TempSession.make()
        let phone = phoneRoot()
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phone) }
        try session.store.appendMotionSamples((0..<5).map { Samples.motion($0) }, sessionId: session.sessionId)
        let incoming = try package(for: session, locations: 5)

        try session.store.importTransferPackage(incoming, intoPhoneStore: phone)

        let manifest = try SessionFileStore(rootURL: phone).readManifest(sessionId: session.sessionId)
        #expect(manifest.motionStoppedReason == nil)
    }
}
