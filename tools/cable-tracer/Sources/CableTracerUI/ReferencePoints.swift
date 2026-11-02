import CableTracerCore
import Foundation
import RpplCore

/// Optional ground truth to show next to the imagery: tower positions fitted from GPS tracks
/// (`towers.csv`: park,corner,turn_deg,lat,lon,…) or dock points (`dock_points.csv`:
/// park,kind,n,lat,lon,…). Any CSV with `park`, `lat` and `lon` columns works.
public struct ReferencePoint: Identifiable, Equatable, Sendable {
    public let id = UUID()
    var parkID: String
    var label: String
    var coordinate: ParkCoordinate
}

public struct ReferencePoints: Equatable, Sendable {
    public init() {}

    public private(set) var all: [ReferencePoint] = []
    private(set) var sourceNames: [String] = []

    func points(for parkID: String) -> [ReferencePoint] { all.filter { $0.parkID == parkID } }

    public mutating func load(csv url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } }
        guard let header = lines.first,
              let parkColumn = header.firstIndex(of: "park"),
              let latColumn = header.firstIndex(of: "lat"),
              let lonColumn = header.firstIndex(of: "lon")
        else { throw CocoaError(.fileReadCorruptFile) }
        lines.removeFirst()
        let labelColumn = header.firstIndex(of: "kind") ?? header.firstIndex(of: "corner")
        let stem = url.deletingPathExtension().lastPathComponent
        for fields in lines where fields.count > max(parkColumn, latColumn, lonColumn) {
            guard let lat = Double(fields[latColumn]), let lon = Double(fields[lonColumn]) else { continue }
            let label = labelColumn.flatMap { fields[safe: $0] } ?? stem
            all.append(ReferencePoint(parkID: fields[parkColumn], label: "\(stem) \(label)", coordinate: ParkCoordinate(lat: lat, lon: lon)))
        }
        sourceNames.append(stem)
    }
}
