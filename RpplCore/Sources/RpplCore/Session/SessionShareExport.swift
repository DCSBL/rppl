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

    /// Share with Rppl filename: `rppl_<timestamp>_anonymized.json`. The place name stays out of it.
    public static func anonymizedFileName(startedAt: Date) -> String {
        fileName(startedAt: startedAt, locationName: "anonymized")
    }

    /// Pretty-printed package bytes; top-level `manifest` is always the first key.
    ///
    /// `JSONEncoder` does not preserve `encode(_:forKey:)` order unless `.sortedKeys` is set,
    /// and `.sortedKeys` would place `detections` before `manifest`. Assemble the object
    /// manually so Share files stay human-scannable.
    public static func encode(_ package: SessionTransferPackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]

        var fields: [(key: String, value: String)] = []
        fields.append(("manifest", try encodeFragment(package.manifest, encoder: encoder)))
        fields.append(("detections", try encodeFragment(package.detections, encoder: encoder)))
        fields.append(("locations", try encodeFragment(package.locations, encoder: encoder)))
        if let motionFramesZlib = package.motionFramesZlib, !motionFramesZlib.isEmpty {
            fields.append(("motionFramesZlib", try encodeFragment(motionFramesZlib, encoder: encoder)))
        } else {
            fields.append(("motion", try encodeFragment(package.motion, encoder: encoder)))
        }
        fields.append(("health", try encodeFragment(package.health, encoder: encoder)))
        if !package.water.isEmpty {
            fields.append(("water", try encodeFragment(package.water, encoder: encoder)))
        }
        if !package.battery.isEmpty {
            fields.append(("battery", try encodeFragment(package.battery, encoder: encoder)))
        }
        if let derived = package.derived {
            fields.append(("derived", try encodeFragment(derived, encoder: encoder)))
        }

        var lines: [String] = ["{"]
        for (index, field) in fields.enumerated() {
            let indented = indentFragment(field.value, by: 2)
            let suffix = index == fields.count - 1 ? "" : ","
            lines.append("  \"\(field.key)\": \(indented)\(suffix)")
        }
        lines.append("}")
        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else {
            throw EncodeError.utf8ConversionFailed
        }
        return data
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

    private enum EncodeError: Error {
        case utf8ConversionFailed
    }

    private static func encodeFragment<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodeError.utf8ConversionFailed
        }
        return string
    }

    /// Pretty fragments are multi-line; bump indent on every line after the first so nesting
    /// under the top-level key stays aligned.
    private static func indentFragment(_ json: String, by spaces: Int) -> String {
        let pad = String(repeating: " ", count: spaces)
        let parts = json.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return json }
        return parts.enumerated().map { index, line in
            index == 0 ? String(line) : pad + line
        }.joined(separator: "\n")
    }
}
