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

    public var parkID: String
    public var name: String
    public var location: ParkCoordinate
    public var cables: [Cable]
    /// 1.4 km overview around the park location.
    public var snapshot: Snapshot?
    /// 600 m close-up around the traced cables; nil for untraced parks.
    public var detailSnapshot: Snapshot?

    public init(park: Park) {
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
    }

    public var hasTracedCable: Bool { cables.contains { $0.geometry.pointsXY.count >= 2 } }
}

public enum TrainingSet {
    public static func rows(parks: [Park], tracedOnly: Bool = true) -> [TrainingRow] {
        parks.map(TrainingRow.init).filter { !tracedOnly || $0.hasTracedCable }
    }

    public static func encode(_ rows: [TrainingRow]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }
}
