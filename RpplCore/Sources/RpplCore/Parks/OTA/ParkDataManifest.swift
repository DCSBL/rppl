import Foundation

public enum ParkDataError: Error, Equatable, Sendable {
    case invalidManifest(String)
    case unsupportedFormat(Int)
    case appUpdateRequired(minSchema: Int)
    case schemaOutOfRange
    case tooLarge(String)
    case hashMismatch(String)
    case missingFile(String)
    case invalidPark(id: String, reason: String)
    case fetchFailed(String)
}

/// `manifest.json` on the `parks-distribution` branch: what the OTA park data consists of.
/// CI writes it whenever park files change; the app never writes it.
public struct ParkDataManifest: Codable, Equatable, Sendable {
    public static let currentFormat = 1
    public static let maxManifestBytes = 512 * 1024
    public static let maxParkFileBytes = 256 * 1024
    public static let maxParks = 500

    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        /// File name inside the same directory as the manifest (`<id>.yaml`).
        public var file: String
        public var sha256: String

        public init(id: String, file: String, sha256: String) {
            self.id = id
            self.file = file
            self.sha256 = sha256
        }
    }

    public var format: Int
    /// Monotonic counter bumped by CI on every change. Any different value than the installed one
    /// installs, so reverting the branch rolls back.
    public var dataVersion: Int
    /// ISO 8601 UTC, when CI produced this manifest. Shown to the rider as "data from".
    public var publishedAt: String
    /// Kill switch: `false` makes the app ignore OTA data and show the bundled parks.
    public var enabled: Bool
    /// Park schema (`Park.version`) range the files in this manifest use.
    public var minAppSchema: Int
    public var maxAppSchema: Int
    public var parks: [Entry]

    public init(
        format: Int = ParkDataManifest.currentFormat,
        dataVersion: Int,
        publishedAt: String,
        enabled: Bool = true,
        minAppSchema: Int = 1,
        maxAppSchema: Int = 1,
        parks: [Entry]
    ) {
        self.format = format
        self.dataVersion = dataVersion
        self.publishedAt = publishedAt
        self.enabled = enabled
        self.minAppSchema = minAppSchema
        self.maxAppSchema = maxAppSchema
        self.parks = parks
    }

    public static func decode(_ data: Data) throws -> ParkDataManifest {
        guard data.count <= maxManifestBytes else { throw ParkDataError.tooLarge("manifest.json") }
        do {
            return try JSONDecoder().decode(ParkDataManifest.self, from: data)
        } catch {
            throw ParkDataError.invalidManifest(error.localizedDescription)
        }
    }

    /// Checks everything that doesn't need the park files. Run before downloading any of them.
    public func validateHeader(appSchema: Int = Park.currentVersion) throws {
        guard format == Self.currentFormat else { throw ParkDataError.unsupportedFormat(format) }
        guard appSchema >= minAppSchema else { throw ParkDataError.appUpdateRequired(minSchema: minAppSchema) }
        guard appSchema <= maxAppSchema else { throw ParkDataError.schemaOutOfRange }
        guard parks.count <= Self.maxParks else { throw ParkDataError.tooLarge("parks") }
        var ids = Set<String>()
        for entry in parks {
            guard Self.isSafeId(entry.id), entry.file == "\(entry.id).yaml" else {
                throw ParkDataError.invalidManifest("bad entry \(entry.id)")
            }
            guard ids.insert(entry.id).inserted else { throw ParkDataError.invalidManifest("duplicate \(entry.id)") }
        }
    }

    /// Parses the downloaded files and checks hash, size, id and schema of each against the manifest.
    @discardableResult
    public func validate(files: [String: Data], appSchema: Int = Park.currentVersion) throws -> [Park] {
        try validateHeader(appSchema: appSchema)
        var result: [Park] = []
        for entry in parks {
            guard let data = files[entry.file] else { throw ParkDataError.missingFile(entry.file) }
            guard data.count <= Self.maxParkFileBytes else { throw ParkDataError.tooLarge(entry.file) }
            guard ParkDataHash.sha256Hex(data) == entry.sha256.lowercased() else {
                throw ParkDataError.hashMismatch(entry.file)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw ParkDataError.invalidPark(id: entry.id, reason: "not UTF-8")
            }
            let park: Park
            do {
                park = try ParkCatalog.parse(yaml: text, fallbackId: entry.id)
            } catch {
                throw ParkDataError.invalidPark(id: entry.id, reason: "\(error)")
            }
            guard park.id == entry.id else { throw ParkDataError.invalidPark(id: entry.id, reason: "id mismatch") }
            guard park.version >= minAppSchema, park.version <= maxAppSchema, park.version <= appSchema else {
                throw ParkDataError.invalidPark(id: entry.id, reason: "schema \(park.version)")
            }
            result.append(park)
        }
        return result
    }

    private static func isSafeId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 80 else { return false }
        return id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" }
            && !id.hasPrefix("-") && !id.hasSuffix("-")
    }
}
