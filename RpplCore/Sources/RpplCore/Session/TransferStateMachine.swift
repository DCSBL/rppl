import Foundation

/// Transfer state only moves forward: `.acknowledged` is terminal (the Watch prunes raw streams
/// after an ack, so regressing would re-send an empty package).
public enum TransferStateMachine {
    public static func isAllowed(
        from current: SessionManifest.TransferState,
        to next: SessionManifest.TransferState
    ) -> Bool {
        current != .acknowledged || next == .acknowledged
    }
}
