import Foundation
import Testing
@testable import RpplCore

@Suite("ICloudLogbookPolicy")
struct ICloudLogbookPolicyTests {
    @Test func peerDeleteSkipsLocalPackagesWhenMetadataPartial() {
        let accepted: Set<String> = ["a", "b", "c"]
        let remote: Set<String> = ["a"]
        let local: Set<String> = ["a", "b", "c"]

        let candidates = ICloudLogbookPolicy.peerDeleteCandidates(
            accepted: accepted,
            remoteMetadata: remote,
            localOnDisk: local,
            metadataGatherComplete: true
        )
        #expect(candidates.isEmpty)
    }

    @Test func peerDeleteSkipsWhenLocalInventoryEmpty() {
        // Empty local listing while accepts remain → unreliable (root switch / lag).
        let candidates = ICloudLogbookPolicy.peerDeleteCandidates(
            accepted: ["gone"],
            remoteMetadata: ["other"],
            localOnDisk: [],
            metadataGatherComplete: true
        )
        #expect(candidates.isEmpty)
    }

    @Test func peerDeleteRemovesAcceptedNotLocalNotRemote() {
        let accepted: Set<String> = ["gone", "keep"]
        let remote: Set<String> = ["keep", "other"]
        let local: Set<String> = ["keep"]

        let candidates = ICloudLogbookPolicy.peerDeleteCandidates(
            accepted: accepted,
            remoteMetadata: remote,
            localOnDisk: local,
            metadataGatherComplete: true
        )
        #expect(candidates == ["gone"])
    }

    @Test func peerDeleteWaitsForGatherComplete() {
        let candidates = ICloudLogbookPolicy.peerDeleteCandidates(
            accepted: ["a"],
            remoteMetadata: [],
            localOnDisk: [],
            metadataGatherComplete: false
        )
        #expect(candidates.isEmpty)
    }

    @Test func reconcileAcceptedUnionsDiskAndPrevious() {
        let result = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: ["a", "old"],
            localIDs: ["a", "b", "imported"]
        )
        #expect(result == ["a", "b", "imported", "old"])
    }

    @Test func reconcileAcceptedSkipsHiddenFromLogbook() {
        let result = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: ["a"],
            localIDs: ["a", "b", "hidden"],
            hiddenFromLogbook: ["hidden"]
        )
        #expect(result == ["a", "b"])
    }

    @Test func remoteImportCandidatesFiltersHiddenFromLogbook() {
        let result = ICloudLogbookPolicy.remoteImportCandidates(
            remoteMetadata: ["a", "b", "hidden"],
            accepted: ["a"],
            dismissed: [],
            hiddenFromLogbook: ["hidden"]
        )
        #expect(result == ["b"])
    }

    @Test func autoAcceptCandidatesSkipsHiddenAndDeclined() {
        let result = ICloudLogbookPolicy.autoAcceptCandidates(
            localOnDisk: ["keep", "hidden", "declined"],
            hiddenFromLogbook: ["hidden"],
            declinedImport: ["declined"]
        )
        #expect(result == ["keep"])
    }

    @Test func remoteImportCandidatesFiltersAcceptedAndDismissed() {
        let result = ICloudLogbookPolicy.remoteImportCandidates(
            remoteMetadata: ["a", "b", "c"],
            accepted: ["a"],
            dismissed: ["b"]
        )
        #expect(result == ["c"])
    }

    @Test func disableImportEnableCycleNoDuplicates() throws {
        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("policy-local-\(UUID().uuidString)", isDirectory: true)
        let cloudRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("policy-cloud-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: localRoot)
            try? FileManager.default.removeItem(at: cloudRoot)
        }

        let localStore = SessionFileStore(rootURL: localRoot)
        _ = try localStore.createSession(
            manifest: SessionManifest(
                sessionId: "watch-a",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "W",
                systemVersion: "26"
            )
        )

        // Disable: copy cloud → local (simulate existing cloud session).
        let cloudStore = SessionFileStore(rootURL: cloudRoot)
        _ = try cloudStore.createSession(
            manifest: SessionManifest(
                sessionId: "watch-a",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "W",
                systemVersion: "26"
            )
        )
        _ = try localStore.createSession(
            manifest: SessionManifest(
                sessionId: "imported-b",
                testerId: "t",
                appVersion: "1",
                buildNumber: "1",
                watchModel: "W",
                systemVersion: "26"
            )
        )

        var accepted: Set<String> = ["watch-a"]
        accepted = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: accepted,
            localIDs: Set(try SessionRootMigrator.sessionIDs(in: localRoot))
        )
        #expect(accepted == ["watch-a", "imported-b"])

        // Enable: copy missing local → cloud.
        let copied = try SessionRootMigrator.copyMissingPackages(from: localRoot, to: cloudRoot)
        #expect(copied == ["imported-b"])
        #expect(Set(try SessionRootMigrator.sessionIDs(in: cloudRoot)) == ["imported-b", "watch-a"])

        accepted = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: accepted,
            localIDs: Set(try SessionRootMigrator.sessionIDs(in: cloudRoot))
        )
        #expect(accepted == ["watch-a", "imported-b"])

        // Partial metadata must not delete locally present packages.
        let deleteCandidates = ICloudLogbookPolicy.peerDeleteCandidates(
            accepted: accepted,
            remoteMetadata: ["watch-a"],
            localOnDisk: Set(try SessionRootMigrator.sessionIDs(in: cloudRoot)),
            metadataGatherComplete: true
        )
        #expect(deleteCandidates.isEmpty)
    }

    @Test func enableDisableEnablePreservesAcceptedUnion() {
        var accepted: Set<String> = ["a", "b"]
        let diskAfterEnable: Set<String> = ["a", "b"]
        accepted = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: accepted,
            localIDs: diskAfterEnable
        )
        #expect(accepted == ["a", "b"])

        // Disable — accepted persists in UserDefaults; disk still has both.
        let diskAfterDisable: Set<String> = ["a", "b"]
        accepted = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: accepted,
            localIDs: diskAfterDisable
        )
        #expect(accepted == ["a", "b"])

        // Re-enable.
        accepted = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: accepted,
            localIDs: diskAfterDisable
        )
        #expect(accepted == ["a", "b"])
    }

    @Test func manualImportThenEnableIncludesImportedID() {
        let accepted = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: [],
            localIDs: ["manual-import"]
        )
        #expect(accepted.contains("manual-import"))
    }
}
