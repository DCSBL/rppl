import Foundation
import RpplCore

/// The park YAML directory the tool edits: normally `RpplCore/Sources/RpplCore/Resources/Parks`.
public struct ParkWorkspace: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Walks up from `start` to the repo root and returns the bundled parks directory, if found.
    public static func locateBundledParks(from start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
        var url = start.standardizedFileURL
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("RpplCore/Sources/RpplCore/Resources/Parks", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    public func fileURL(for parkID: String) -> URL {
        directory.appendingPathComponent("\(parkID).yaml")
    }

    public func load() -> [Park] {
        ParkCatalog.loadDirectory(directory).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Writes the park back with a history line, the way every other park edit in the repo is recorded.
    public func save(_ park: Park, historyDescription: String, date: Date = Date()) throws {
        var park = park
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var history = park.history ?? []
        history.append(ParkHistoryEntry(date: formatter.string(from: date), description: historyDescription))
        park.history = history
        let yaml = try ParkCatalog.encode(park)
        try yaml.write(to: fileURL(for: park.id), atomically: true, encoding: .utf8)
    }
}
