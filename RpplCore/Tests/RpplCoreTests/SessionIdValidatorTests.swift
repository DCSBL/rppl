import Foundation
import Testing
@testable import RpplCore

@Suite("SessionIdValidator")
struct SessionIdValidatorTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sid-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func acceptsUUID() throws {
        let id = UUID().uuidString
        try SessionIdValidator.validate(id)
        #expect(SessionIdValidator.isValid(id))
    }

    @Test func rejectsEmpty() {
        #expect(throws: SessionStoreError.invalidSessionId("")) {
            try SessionIdValidator.validate("")
        }
    }

    @Test func rejectsPathSeparators() {
        #expect(throws: SessionStoreError.invalidSessionId("../escape")) {
            try SessionIdValidator.validate("../escape")
        }
        #expect(throws: SessionStoreError.invalidSessionId("a/b")) {
            try SessionIdValidator.validate("a/b")
        }
        #expect(throws: SessionStoreError.invalidSessionId("a\\b")) {
            try SessionIdValidator.validate("a\\b")
        }
    }

    @Test func resolvedDirectoryStaysUnderRoot() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let dir = try SessionIdValidator.sessionDirectory(for: id, rootURL: root)
        #expect(dir.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path))
    }

    @Test func importRejectsBadSessionId() throws {
        let watchRoot = tempRoot().appendingPathComponent("watch", isDirectory: true)
        let phoneRoot = tempRoot().appendingPathComponent("phone", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: watchRoot.deletingLastPathComponent())
        }

        let watchStore = SessionFileStore(rootURL: watchRoot)
        let manifest = SessionManifest(
            sessionId: "../evil",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        let package = SessionTransferPackage(
            manifest: manifest,
            detections: [],
            locations: [],
            health: []
        )

        #expect(throws: SessionStoreError.invalidSessionId("../evil")) {
            try watchStore.importTransferPackage(package, intoPhoneStore: phoneRoot)
        }
    }
}
