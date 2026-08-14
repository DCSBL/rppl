import Foundation

public enum TransferPendingFilter {
    /// Manifests that still need a successful phone ack.
    public static func needingTransfer(_ manifests: [SessionManifest]) -> [SessionManifest] {
        manifests.filter { manifest in
            switch manifest.transferState {
            case .readyToTransfer, .transferring:
                return true
            case .recording, .acknowledged:
                return false
            }
        }
    }
}
