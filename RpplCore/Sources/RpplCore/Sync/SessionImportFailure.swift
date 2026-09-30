import Foundation

/// Short, stable reason the phone sends back when a Watch package cannot be imported. Stored in
/// the Watch manifest (`lastTransferError`) for diagnosis; bounded so userInfo stays small.
public enum SessionImportFailure {
    public static let maxReasonLength = 200

    public static func reason(for error: Error) -> String {
        let text: String
        if let store = error as? SessionStoreError {
            text = "store: \(store)"
        } else if let frames = error as? CompressedJSONLFrameError {
            text = "motion: \(frames)"
        } else if error is DecodingError {
            text = "decode: \(error)"
        } else {
            text = error.localizedDescription
        }
        return String(text.prefix(maxReasonLength))
    }
}
