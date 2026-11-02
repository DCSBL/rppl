import AppKit
import CableTracerCore
import CoreGraphics
import MapKit
import RpplCore

/// Renders the satellite image a park was traced on, plus a black/white mask of its cables,
/// at a fixed ground scale so every example in the training set is comparable.
enum SnapshotExporter {
    static let sizePx = 1024
    /// 1.4 km square: a full-size loop plus margin, at 1.37 m per pixel.
    static let groundSizeM = 1400.0

    @MainActor
    static func export(row: TrainingRow, into directory: URL) async throws -> TrainingRow.Snapshot {
        let center = CLLocationCoordinate2D(latitude: row.location.lat, longitude: row.location.lon)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, latitudinalMeters: groundSizeM, longitudinalMeters: groundSizeM)
        options.size = CGSize(width: sizePx, height: sizePx)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        options.showsBuildings = false
        let snapshot = try await MKMapSnapshotter(options: options).start()

        let imageFile = "\(row.parkID).png"
        try write(snapshot.image, to: directory.appendingPathComponent(imageFile))

        var maskFile: String?
        let projection = LocalProjection(origin: row.location)
        let traced = row.cables.filter { $0.geometry.pointsXY.count >= 2 }
        if !traced.isEmpty {
            let mask = NSImage(size: options.size, flipped: false) { rect in
                NSColor.black.setFill()
                rect.fill()
                NSColor.white.setStroke()
                for cable in traced {
                    let path = NSBezierPath()
                    path.lineWidth = 6
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    for (index, xy) in cable.geometry.pointsXY.enumerated() {
                        let coordinate = projection.coordinate(xy)
                        // MKMapSnapshot.point(for:) is already bottom-left based on macOS, matching this non-flipped image.
                        let point = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon))
                        if index == 0 { path.move(to: point) } else { path.line(to: point) }
                    }
                    if cable.geometry.isClosed { path.close() }
                    path.stroke()
                }
                return true
            }
            maskFile = "\(row.parkID)-mask.png"
            try write(mask, to: directory.appendingPathComponent(maskFile!))
        }

        return TrainingRow.Snapshot(
            imageFile: imageFile,
            maskFile: maskFile,
            sizePx: sizePx,
            metersPerPixel: groundSizeM / Double(sizePx),
            center: row.location
        )
    }

    private static func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
