import Foundation

/// Lean slice of a phone export for Assumer / GPS analysis (motion/health unused).
public struct AnalysisPackage: Codable, Equatable, Sendable {
    public var manifest: SessionManifest
    public var assumptions: [AssumptionEvent]
    public var locations: [LocationSample]

    public init(
        manifest: SessionManifest,
        assumptions: [AssumptionEvent],
        locations: [LocationSample]
    ) {
        self.manifest = manifest
        self.assumptions = assumptions
        self.locations = locations
    }
}

public enum SessionExportLoader {
    public enum LoadError: LocalizedError, Equatable {
        case empty
        case invalidJSON

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Export file is empty"
            case .invalidJSON:
                return "Export JSON could not be parsed"
            }
        }
    }

    private static let heavyKeys: [String] = [
        "motionFramesZlib",
        "motion",
        "health",
        "labels"
    ]

    public static func load(from data: Data) throws -> AnalysisPackage {
        guard !data.isEmpty else { throw LoadError.empty }
        let trimmed = try stripTopLevelKeys(data, keys: heavyKeys)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(AnalysisPackage.self, from: trimmed)
        } catch {
            throw LoadError.invalidJSON
        }
    }

    public static func load(fromFile url: URL) throws -> AnalysisPackage {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try load(from: data)
    }

    /// Drop selected top-level keys by byte rewrite — never builds an object graph of motion blobs.
    static func stripTopLevelKeys(_ data: Data, keys: [String]) throws -> Data {
        var bytes = [UInt8](data)
        for key in keys {
            bytes = try removeTopLevelKey(bytes, key: key)
        }
        return Data(bytes)
    }

    private static func removeTopLevelKey(_ bytes: [UInt8], key: String) throws -> [UInt8] {
        let needle = Array("\"\(key)\"".utf8)
        guard let keyIndex = findTopLevelKey(bytes, needle: needle) else {
            return bytes
        }

        // Include a preceding comma if present.
        var removeStart = keyIndex
        var k = keyIndex - 1
        while k >= 0, isWhitespace(bytes[k]) { k -= 1 }
        if k >= 0, bytes[k] == UInt8(ascii: ",") {
            removeStart = k
        }

        var i = keyIndex + needle.count
        i = skipWhitespace(bytes, from: i)
        guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else {
            throw LoadError.invalidJSON
        }
        i += 1
        i = skipWhitespace(bytes, from: i)
        let valueEnd = try skipValue(bytes, from: i)

        // If no preceding comma, drop a following comma so JSON stays valid.
        var removeEnd = valueEnd
        if removeStart == keyIndex {
            let j = skipWhitespace(bytes, from: valueEnd)
            if j < bytes.count, bytes[j] == UInt8(ascii: ",") {
                removeEnd = j + 1
            }
        }

        var out = [UInt8]()
        out.reserveCapacity(bytes.count - (removeEnd - removeStart))
        out.append(contentsOf: bytes[..<removeStart])
        out.append(contentsOf: bytes[removeEnd...])
        return out
    }

    /// Find `"key"` only at JSON object depth 1 (top-level members).
    private static func findTopLevelKey(_ bytes: [UInt8], needle: [UInt8]) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if inString {
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "\"") {
                    inString = false
                }
                i += 1
                continue
            }
            switch b {
            case UInt8(ascii: "\""):
                if depth == 1, matches(bytes, at: i, needle: needle) {
                    return i
                }
                inString = true
                i += 1
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                i += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                i += 1
            default:
                i += 1
            }
        }
        return nil
    }

    private static func matches(_ bytes: [UInt8], at index: Int, needle: [UInt8]) -> Bool {
        guard index + needle.count <= bytes.count else { return false }
        for offset in 0..<needle.count where bytes[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    private static func skipValue(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard start < bytes.count else { throw LoadError.invalidJSON }
        let b = bytes[start]
        switch b {
        case UInt8(ascii: "\""):
            var i = start + 1
            var escaped = false
            while i < bytes.count {
                let c = bytes[i]
                if escaped {
                    escaped = false
                } else if c == UInt8(ascii: "\\") {
                    escaped = true
                } else if c == UInt8(ascii: "\"") {
                    return i + 1
                }
                i += 1
            }
            throw LoadError.invalidJSON

        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var i = start
            var depth = 0
            var inString = false
            var escaped = false
            while i < bytes.count {
                let c = bytes[i]
                if inString {
                    if escaped {
                        escaped = false
                    } else if c == UInt8(ascii: "\\") {
                        escaped = true
                    } else if c == UInt8(ascii: "\"") {
                        inString = false
                    }
                    i += 1
                    continue
                }
                switch c {
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default:
                    break
                }
                i += 1
            }
            throw LoadError.invalidJSON

        default:
            var i = start
            while i < bytes.count {
                let c = bytes[i]
                if isWhitespace(c)
                    || c == UInt8(ascii: ",")
                    || c == UInt8(ascii: "}")
                    || c == UInt8(ascii: "]") {
                    break
                }
                i += 1
            }
            return i
        }
    }

    private static func skipWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
        var i = start
        while i < bytes.count, isWhitespace(bytes[i]) { i += 1 }
        return i
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09
    }
}
