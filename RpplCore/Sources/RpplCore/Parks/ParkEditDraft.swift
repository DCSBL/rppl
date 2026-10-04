import Foundation

/// A park being written in the editor that is not saved as a park yet: possibly without a name or a
/// location, with half-filled lists. Stored apart from park files so an unfinished entry never
/// shows up as a park, and so closing or killing the app loses nothing.
public struct ParkEditDraft: Codable, Equatable, Identifiable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// File-name safe, see `ParkDraftStore.fileName(for:)`.
    public var id: String
    /// `id` of the park this draft edits; nil when it creates a new park.
    public var editsParkID: String?
    public var park: Park
    /// The page of the guided flow the person was on; nil in free editing.
    public var step: Int?
    public var savedAt: Date

    public init(
        id: String,
        editsParkID: String? = nil,
        park: Park,
        step: Int? = nil,
        savedAt: Date = Date(),
        version: Int = ParkEditDraft.currentVersion
    ) {
        self.version = version
        self.id = id
        self.editsParkID = editsParkID
        self.park = park
        self.step = step
        self.savedAt = savedAt
    }

    /// A draft id for a new park.
    public static func newID() -> String { "new-" + UUID().uuidString.lowercased() }

    /// The one draft an existing park can have.
    public static func editID(forPark parkID: String) -> String { "edit-" + ParkDraftStore.safeComponent(parkID) }

    public var title: String {
        let name = park.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "" : name
    }
}

/// Reads and writes `ParkEditDraft` files in one folder. Failures never throw out of reads: a file
/// that cannot be read is skipped and logged, like a bad park YAML.
public struct ParkDraftStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Larger files are not ours.
    static let maxFileBytes = 2_000_000

    /// Letters, digits, `-` and `_` only, so an id can never leave the folder.
    static func safeComponent(_ text: String) -> String {
        let mapped = text.lowercased().unicodeScalars.map { scalar -> Character in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"))
                ? Character(scalar) : "-"
        }
        let result = String(mapped)
        return result.isEmpty ? "park" : String(result.prefix(100))
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 140 && id == safeComponent(id)
    }

    func fileURL(for id: String) -> URL? {
        Self.isValidID(id) ? directory.appendingPathComponent(id + ".json") : nil
    }

    public func save(_ draft: ParkEditDraft) throws {
        guard let url = fileURL(for: draft.id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(draft).write(to: url, options: .atomic)
    }

    public func load(id: String) -> ParkEditDraft? {
        guard let url = fileURL(for: id) else { return nil }
        return read(url)
    }

    /// Newest first.
    public func all() -> [ParkEditDraft] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap(read).sorted { $0.savedAt > $1.savedAt }
    }

    public func delete(id: String) {
        guard let url = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func read(_ url: URL) -> ParkEditDraft? {
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maxFileBytes else { return nil }
            let draft = try Self.decoder.decode(ParkEditDraft.self, from: Data(contentsOf: url))
            // The file name is the id: a copied or renamed file would otherwise overwrite another draft.
            guard Self.isValidID(draft.id), url.deletingPathExtension().lastPathComponent == draft.id else { return nil }
            return draft
        } catch {
            WakeLog.error(.store, "park draft \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
