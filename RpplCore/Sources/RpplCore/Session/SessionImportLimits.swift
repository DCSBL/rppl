import Foundation

/// Bounds for Share export / WC transfer JSON and nested arrays.
public enum SessionImportLimits {
    public static let maxTransferJSONBytes = 128 * 1024 * 1024
    public static let maxDetections = 50_000
    public static let maxLocations = 500_000
    public static let maxMotionSamples = 2_000_000
    public static let maxHealthSamples = 200_000
    public static let maxWaterSamples = 20_000
    public static let maxBatterySamples = 20_000
    public static let maxMotionFramesZlibBytes = 64 * 1024 * 1024
    public static let maxHeatmapTrackCount = 100
    public static let maxHeatmapPointsPerTrack = 10_000

    public static func readBoundedFile(at url: URL, maxBytes: Int = maxTransferJSONBytes) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > maxBytes {
            throw SessionStoreError.importTooLarge(fileSize)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maxBytes else {
            throw SessionStoreError.importTooLarge(data.count)
        }
        return data
    }

    public static func decodeTransferPackage(from data: Data) throws -> SessionTransferPackage {
        guard data.count <= maxTransferJSONBytes else {
            throw SessionStoreError.importTooLarge(data.count)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionTransferPackage.self, from: data)
    }

    public static func validateArrayCount<T>(_ array: [T], limit: Int, label: String) throws {
        guard array.count <= limit else {
            throw SessionStoreError.importLimitExceeded("\(label) count \(array.count) > \(limit)")
        }
    }

    public static func validateHeatmapTracks(_ tracks: [[MapCoordinate]]) throws {
        try validateArrayCount(tracks, limit: maxHeatmapTrackCount, label: "heatmapTracks")
        for (index, track) in tracks.enumerated() {
            guard track.count <= maxHeatmapPointsPerTrack else {
                throw SessionStoreError.importLimitExceeded(
                    "heatmapTracks[\(index)] count \(track.count) > \(maxHeatmapPointsPerTrack)"
                )
            }
        }
    }
}
