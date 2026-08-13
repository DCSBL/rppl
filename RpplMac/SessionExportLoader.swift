import Foundation
import RpplCore

/// Lean decode of export JSON — ignores motion/health/labels (extra keys skipped).
struct AnalysisPackage: Decodable, Sendable {
    var manifest: SessionManifest
    var assumptions: [AssumptionEvent]
    var locations: [LocationSample]
}

enum SessionExportLoader {
    enum LoadError: LocalizedError {
        case notJSONObject

        var errorDescription: String? {
            switch self {
            case .notJSONObject:
                return "Export root is not a JSON object"
            }
        }
    }

    /// Drop heavy unused keys before Codable decode (motion blob ~MBs).
    static func load(from data: Data) throws -> AnalysisPackage {
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
}
