import Foundation

/// iPhone Share export: human-readable `SessionTransferPackage` JSON.
///
/// Filename: `rppl_<timestamp>_<location>.json` — UTC start time, city slug (or `unknown`).
/// Body: pretty-printed; top-level `manifest` first (no `sortedKeys`).
public enum SessionShareExport {
    /// Share filename: `rppl_<ISO8601-UTC-with-colons-as-dashes>_<location>.json`.
    public static func fileName(startedAt: Date, locationName: String?) -> String {
        // Local formatter — `ISO8601DateFormatter` is not Sendable; avoid static shared state.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let raw = formatter.string(from: startedAt)
        let timestamp = raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let location = sanitizeLocation(locationName)
        return "rppl_\(timestamp)_\(location).json"
    }

    /// Pretty-printed package bytes; encode order keeps `manifest` as the first key.
    public static func encode(_ package: SessionTransferPackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(package)
    }

    /// Filesystem-safe location segment; empty / nil → `unknown`.
    public static func sanitizeLocation(_ locationName: String?) -> String {
        let trimmed = (locationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(trimmed.unicodeScalars.count)
        var pendingSeparator = false
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !scalars.isEmpty {
                    scalars.append("-")
                    pendingSeparator = false
                }
                scalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        let slug = String(String.UnicodeScalarView(scalars))
        return slug.isEmpty ? "unknown" : slug
    }
}
