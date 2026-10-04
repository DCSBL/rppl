import Foundation

/// Delivery rules for "Share with Rppl" by mail. UI-free, so the decision tree lives here and
/// the phone only reports what the device can do (`MFMailComposeViewController.canSendMail()`).
public enum SessionShareMail {
    /// How the anonymized session leaves the phone.
    public enum Route: Equatable, Sendable {
        /// Native mail composer with the session file attached.
        case attachment
        /// `mailto:` link with the file base64-encoded in the body, for a phone without a
        /// configured Mail account. A `mailto:` link cannot carry an attachment.
        case base64Body
        /// System share sheet with the file. Last resort when the base64 body would be too long.
        case shareSheet
    }

    /// Longest base64 body a `mailto:` link may carry. Mail apps drop or truncate very long
    /// links, so a bigger session goes to the share sheet instead.
    public static let maxBase64BodyLength = 256 * 1024

    /// Base64 line width. Mail transport can rewrite or reject extremely long lines.
    private static let base64LineLength = 76

    public static func route(canSendMail: Bool, fileByteCount: Int) -> Route {
        if canSendMail { return .attachment }
        return base64BodyLength(forByteCount: fileByteCount) <= maxBase64BodyLength ? .base64Body : .shareSheet
    }

    /// The file as base64 text, wrapped in lines of 76 characters. Decoders skip the line breaks.
    public static func base64Body(for data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
    }

    /// Upper bound for `base64Body(for:)` of `byteCount` bytes, line breaks included.
    public static func base64BodyLength(forByteCount byteCount: Int) -> Int {
        let characters = (max(byteCount, 0) + 2) / 3 * 4
        let lineBreaks = (characters + base64LineLength - 1) / base64LineLength
        return characters + lineBreaks
    }

    /// `mailto:` link with subject and body.
    ///
    /// Everything except unreserved ASCII is percent-encoded, `+` included. `URLComponents` leaves
    /// `+` alone in query values, and some mail apps read it as a space, which corrupts base64.
    public static func mailtoURL(recipient: String, subject: String, body: String) -> URL? {
        let address = percentEncoded(recipient).replacingOccurrences(of: "%40", with: "@")
        return URL(string: "mailto:\(address)?subject=\(percentEncoded(subject))&body=\(percentEncoded(body))")
    }

    private static func percentEncoded(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                result.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                let hex = String(byte, radix: 16, uppercase: true)
                result += byte < 16 ? "%0\(hex)" : "%\(hex)"
            }
        }
        return result
    }
}
