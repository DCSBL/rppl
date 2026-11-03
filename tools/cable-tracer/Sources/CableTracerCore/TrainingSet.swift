import Foundation
import RpplCore

/// One park as a learning example: its location, every cable in local metres with shape
/// statistics, and (filled in by the app) the satellite snapshot the cables were traced on.
public struct TrainingRow: Codable, Equatable, Sendable {
    public struct Cable: Codable, Equatable, Sendable {
        public var name: String?
        public var direction: String?
        public var declaredLengthM: Double?
        public var geometry: CableGeometry
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        /// File names relative to the export directory.
        public var imageFile: String
        public var maskFile: String?
        public var sizePx: Int
        public var metersPerPixel: Double
        /// Snapshot centre; the park location unless the cables pulled it elsewhere.
        public var center: ParkCoordinate

        public init(imageFile: String, maskFile: String?, sizePx: Int, metersPerPixel: Double, center: ParkCoordinate) {
            self.imageFile = imageFile
            self.maskFile = maskFile
            self.sizePx = sizePx
            self.metersPerPixel = metersPerPixel
            self.center = center
        }
    }

    /// A reviewed tower position in local metres (see `TowerLabel`).
    public struct Tower: Codable, Equatable, Sendable {
        public var xy: SIMD2<Double>
        public var verdict: String
        public var source: String
        public var probability: Double?
    }

    public var parkID: String
    public var name: String
    public var location: ParkCoordinate
    public var cables: [Cable]
    /// Tower labels from the review mode; absent when the park has none.
    public var towers: [Tower]?
    /// 1.4 km overview around the park location.
    public var snapshot: Snapshot?
    /// 600 m close-up around the traced cables; nil for untraced parks.
    public var detailSnapshot: Snapshot?

    public init(park: Park, labels: [TowerLabel] = []) {
        parkID = park.id
        name = park.name
        location = park.location
        cables = (park.cables ?? []).map { cable in
            Cable(
                name: cable.name,
                direction: cable.direction?.rawValue,
                declaredLengthM: cable.lengthM,
                geometry: CableGeometry(cable: cable, parkLocation: park.location)
            )
        }
        if !labels.isEmpty {
            let projection = LocalProjection(origin: park.location)
            towers = labels.map { Tower(xy: projection.xy($0.coordinate), verdict: $0.verdict.rawValue, source: $0.source.rawValue, probability: $0.probability) }
        }
    }

    public var hasTracedCable: Bool { cables.contains { $0.geometry.pointsXY.count >= 2 } }
    public var hasTowerLabels: Bool { !(towers ?? []).isEmpty }
    /// Where the 600 m close-up goes: around the traced cables and the reviewed towers.
    public var detailCenterXY: SIMD2<Double>? {
        let points = cables.flatMap(\.geometry.pointsXY) + (towers ?? []).filter { $0.verdict != "unsure" }.map(\.xy)
        guard !points.isEmpty else { return nil }
        return points.reduce(SIMD2<Double>.zero, +) / Double(points.count)
    }
}

public enum TrainingSet {
    /// One row per park; with `tracedOnly` just the parks that have a traced cable or reviewed towers.
    public static func rows(parks: [Park], labels: TowerLabelStore = TowerLabelStore(), tracedOnly: Bool = true) -> [TrainingRow] {
        parks.map { TrainingRow(park: $0, labels: labels.labels(for: $0.id)) }.filter { !tracedOnly || $0.hasTracedCable || $0.hasTowerLabels }
    }

    public static func encode(_ rows: [TrainingRow]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }
}
