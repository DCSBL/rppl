import Foundation

/// Single rule for when a phone view-sync reply may delete a Watch session package.
/// Hard constraint 2: never delete Watch session files until the phone acked the transfer.
public enum WatchViewDeletePolicy {
    public static func mayDelete(_ manifest: SessionManifest) -> Bool {
        manifest.transferState == .acknowledged
    }
}
