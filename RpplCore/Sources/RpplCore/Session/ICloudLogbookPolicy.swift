import Foundation

/// Pure iCloud logbook accept-set and peer-delete rules (testable without NSMetadataQuery).
public enum ICloudLogbookPolicy {
    /// Session ids safe to drop after a peer removed them from iCloud Drive.
    /// Never includes packages still present on disk — metadata can lag behind upload.
    /// Empty `localOnDisk` while `accepted` is non-empty is treated as an unreliable
    /// inventory (root switch / ubiquity lag) — never peer-delete in that state.
    public static func peerDeleteCandidates(
        accepted: Set<String>,
        remoteMetadata: Set<String>,
        localOnDisk: Set<String>,
        metadataGatherComplete: Bool
    ) -> Set<String> {
        guard metadataGatherComplete, !remoteMetadata.isEmpty else { return [] }
        // Empty local listing with leftover accepts → do not unaccept (logbook would go blank).
        if localOnDisk.isEmpty, !accepted.isEmpty { return [] }
        return accepted.subtracting(remoteMetadata).subtracting(localOnDisk)
    }

    /// Union previous accepted ids with every package on disk after enable / migrate.
    public static func reconcileAccepted(
        previousAccepted: Set<String>,
        localIDs: Set<String>
    ) -> Set<String> {
        previousAccepted.union(localIDs)
    }

    /// Remote session ids that should appear in the import picker.
    public static func remoteImportCandidates(
        remoteMetadata: Set<String>,
        accepted: Set<String>,
        dismissed: Set<String>
    ) -> Set<String> {
        remoteMetadata.subtracting(accepted).subtracting(dismissed)
    }
}
