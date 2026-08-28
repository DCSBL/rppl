import Foundation

/// Lightweight list row for iCloud Drive import picker (manifest + derived view only).
public struct RemoteSessionSummary: Equatable, Identifiable, Sendable {
    public var id: String { sessionId }
    public var sessionId: String
    public var startedAt: Date
    public var cityName: String?
    public var setCount: Int
    public var totalDuration: TimeInterval

    public init(
        sessionId: String,
        startedAt: Date,
        cityName: String? = nil,
        setCount: Int = 0,
        totalDuration: TimeInterval = 0
    ) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.cityName = cityName
        self.setCount = setCount
        self.totalDuration = totalDuration
    }
}

public enum RemoteSessionSummaryReader {
    /// Reads `manifest.json` and optional `derived/view.json` under a session package directory.
    public static func read(
        sessionDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> RemoteSessionSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestURL = sessionDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SessionStoreError.sessionNotFound(sessionDirectory.lastPathComponent)
        }
        let manifest = try decoder.decode(SessionManifest.self, from: Data(contentsOf: manifestURL))

        var cityName: String?
        var setCount = 0
        var totalDuration: TimeInterval = 0
        if let ended = manifest.endedAt {
            totalDuration = max(0, ended.timeIntervalSince(manifest.startedAt))
        }

        let viewURL = sessionDirectory
            .appendingPathComponent("derived", isDirectory: true)
            .appendingPathComponent("view.json")
        if fileManager.fileExists(atPath: viewURL.path),
           let view = try? decoder.decode(DerivedSessionView.self, from: Data(contentsOf: viewURL)) {
            cityName = view.cityName
            setCount = view.stats.setCount
            totalDuration = view.stats.totalDuration
        }

        return RemoteSessionSummary(
            sessionId: manifest.sessionId,
            startedAt: manifest.startedAt,
            cityName: cityName,
            setCount: setCount,
            totalDuration: totalDuration
        )
    }
}
