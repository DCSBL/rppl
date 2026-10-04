import Foundation
import Testing
@testable import RpplCore

/// Regression guardrails for DCSBL-72 / DCSBL-73 / DCSBL-76 — malicious inputs must
/// reject before unbounded decode, decompression, or path escape.
@Suite("SecurityRegression", .serialized)
struct SecurityRegressionTests {
    private func tempRoot(label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Sparse on-disk payload: `readBoundedFile` checks `.fileSizeKey` before mapping bytes.
    private func sparseFile(byteCount: Int, label: String) throws -> URL {
        let url = tempRoot(label: label).appendingPathComponent("package.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(byteCount))
        try handle.close()
        return url
    }

    /// Length-prefixed frame claiming `claimedCompressedBytes` with minimal trailing bytes.
    private func maliciousZlibFrame(claimedCompressedBytes: UInt32) -> Data {
        var frame = Data()
        var be = claimedCompressedBytes.bigEndian
        withUnsafeBytes(of: &be) { frame.append(contentsOf: $0) }
        frame.append(Data(repeating: 0x00, count: 8))
        return frame
    }

    // MARK: - Path traversal (DCSBL-72)

    @Test func storeRejectsTraversalSessionIdOnCreate() {
        let root = tempRoot(label: "traversal-create")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "../escape",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )

        #expect(throws: SessionStoreError.invalidSessionId("../escape")) {
            try store.createSession(manifest: manifest)
        }
    }

    @Test func storeRejectsTraversalSessionIdOnDelete() {
        let root = tempRoot(label: "traversal-delete")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        #expect(throws: SessionStoreError.invalidSessionId("../escape")) {
            try store.deleteSession(sessionId: "../escape")
        }
    }

    @Test func importRejectsTraversalSessionId() throws {
        let watchRoot = tempRoot(label: "traversal-import-watch")
        let phoneRoot = tempRoot(label: "traversal-import-phone")
        defer {
            try? FileManager.default.removeItem(at: watchRoot)
            try? FileManager.default.removeItem(at: phoneRoot)
        }

        let store = SessionFileStore(rootURL: watchRoot)
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                sessionId: "../../outside",
                testerId: "t",
                appVersion: "1.0",
                buildNumber: "1",
                watchModel: "Ultra2",
                systemVersion: "26.0"
            ),
            detections: [],
            locations: [],
            health: []
        )

        #expect(throws: SessionStoreError.invalidSessionId("../../outside")) {
            try store.importTransferPackage(package, intoPhoneStore: phoneRoot)
        }
        #expect(FileManager.default.fileExists(atPath: phoneRoot.path) == false)
    }

    @Test func watchViewDeleteRejectsTraversalSessionId() {
        let message = WatchViewSyncCodec.encodeViewDelete(sessionId: "../escape")
        #expect(throws: SessionStoreError.invalidSessionId("../escape")) {
            _ = try WatchViewSyncCodec.decodeViewDelete(from: message)
        }
    }

    @Test func listSessionIDsIgnoresInvalidDirectoryNames() throws {
        let root = tempRoot(label: "traversal-list")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bad..id", isDirectory: true),
            withIntermediateDirectories: true
        )
        // UUID folder without manifest is ignored (discovery requires manifest.json).
        let orphanId = UUID().uuidString
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(orphanId, isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0"
        )
        _ = try store.createSession(manifest: manifest)

        let ids = try store.listSessionIDs()
        #expect(ids == [manifest.sessionId])
        #expect(!ids.contains(orphanId))
    }

    // MARK: - Oversize JSON import (DCSBL-76)

    @Test func readBoundedFileRejectsSparseOversizeBeforeMapping() throws {
        let limit = 1024
        let oversize = limit + 1
        let url = try sparseFile(byteCount: oversize, label: "oversize-read")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: SessionStoreError.importTooLarge(oversize)) {
            _ = try SessionImportLimits.readBoundedFile(at: url, maxBytes: limit)
        }
    }

    @Test func sessionLoaderRejectsSparseOversizePackage() throws {
        let limit = 1024
        let oversize = limit + 1
        let url = try sparseFile(byteCount: oversize, label: "oversize-loader")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        #expect(values.fileSize == oversize)
        #expect(throws: SessionStoreError.importTooLarge(oversize)) {
            _ = try SessionImportLimits.readBoundedFile(at: url, maxBytes: limit)
        }
    }

    // MARK: - Malicious zlib (DCSBL-73)

    @Test func decodeFramesRejectsOversizedLengthWithoutDecompressing() {
        let bomb = maliciousZlibFrame(claimedCompressedBytes: UInt32(CompressedJSONLFrames.maxCompressedBytesPerFrame + 1))
        #expect(bomb.count < 256)
        #expect(throws: CompressedJSONLFrameError.frameTooLarge) {
            _ = try CompressedJSONLFrames.decodeFrames(bomb)
        }
    }

    @Test func writeMotionFrameDataDropsMaliciousZlibWithoutThrowing() throws {
        let root = tempRoot(label: "zlib-store")
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

        let bomb = maliciousZlibFrame(claimedCompressedBytes: UInt32(CompressedJSONLFrames.maxCompressedBytesPerFrame + 1))
        let dropped = try store.writeMotionFrameData(bomb, sessionId: manifest.sessionId)
        #expect(dropped == bomb.count)
        #expect(try store.readMotionFrameData(sessionId: manifest.sessionId) == nil)
    }

    @Test func importDropsMaliciousMotionFramesZlibButKeepsTheSession() throws {
        let watchRoot = tempRoot(label: "zlib-import-watch")
        let phoneRoot = tempRoot(label: "zlib-import-phone")
        defer {
            try? FileManager.default.removeItem(at: watchRoot)
            try? FileManager.default.removeItem(at: phoneRoot)
        }

        let store = SessionFileStore(rootURL: watchRoot)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        let bomb = maliciousZlibFrame(claimedCompressedBytes: UInt32(CompressedJSONLFrames.maxCompressedBytesPerFrame + 1))
        let package = SessionTransferPackage(
            manifest: manifest,
            detections: [],
            locations: [],
            motionFramesZlib: bomb,
            health: []
        )

        try store.importTransferPackage(package, intoPhoneStore: phoneRoot)

        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.readMotionFrameData(sessionId: manifest.sessionId) == nil)
        let imported = try phone.readManifest(sessionId: manifest.sessionId)
        #expect(imported.motionStoppedReason == MotionRecordingPolicy.Reason.importLimit)
        #expect(imported.transferState == .acknowledged)
    }
}
