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
        case notJSONObject

        public var errorDescription: String? {
            switch self {
            case .notJSONObject:
                return "Export root is not a JSON object"
            }
        }
    }

    /// Drop heavy unused keys before Codable decode (motion blob can be many MB).
    public static func load(from data: Data) throws -> AnalysisPackage {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.notJSONObject
        }
        root.removeValue(forKey: "motionFramesZlib")
        root.removeValue(forKey: "motion")
        root.removeValue(forKey: "health")
        root.removeValue(forKey: "labels")
        let trimmed = try JSONSerialization.data(withJSONObject: root)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AnalysisPackage.self, from: trimmed)
    }

    public static func load(fromFile url: URL) throws -> AnalysisPackage {
        try load(from: Data(contentsOf: url))
    }
}
