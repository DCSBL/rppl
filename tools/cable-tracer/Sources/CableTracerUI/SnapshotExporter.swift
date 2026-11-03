import CableTracerCore
import CoreGraphics
import MapKit
import RpplCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the satellite image a park was traced on, plus a black/white mask of its cables,
/// at fixed ground scales so every example in the training set is comparable.
public enum SnapshotExporter {
    public struct Scale: Sendable {
        public var suffix: String
        public var sizePx: Int
        public var groundSizeM: Double
        public var metersPerPixel: Double { groundSizeM / Double(sizePx) }
    }

    /// 1.4 km square around the park location at 1.37 m/px: context, water and obstacles, but
    /// the cable itself is not visible at this scale (checked 2026-11-02 on Almere and Rotterdam).
    public static let overview = Scale(suffix: "", sizePx: 1024, groundSizeM: 1400)
    /// 600 m square around the traced cables at 0.29 m/px: the most Apple imagery gives, for masts and boats.
    public static let detail = Scale(suffix: "-detail", sizePx: 2048, groundSizeM: 600)

    @MainActor
    public static func export(row: TrainingRow, into directory: URL) async throws -> (overview: TrainingRow.Snapshot, detail: TrainingRow.Snapshot?) {
        let overview = try await export(row: row, scale: Self.overview, center: row.location, into: directory)
        var detail: TrainingRow.Snapshot?
        if let centerXY = row.detailCenterXY {
            let center = LocalProjection(origin: row.location).coordinate(centerXY)
            detail = try await export(row: row, scale: Self.detail, center: center, into: directory)
        }
        return (overview, detail)
    }

    @MainActor
    static func export(row: TrainingRow, scale: Scale, center: ParkCoordinate, into directory: URL) async throws -> TrainingRow.Snapshot {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon),
            latitudinalMeters: scale.groundSizeM, longitudinalMeters: scale.groundSizeM
        )
        options.size = CGSize(width: scale.sizePx, height: scale.sizePx)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        options.showsBuildings = false
        #if os(macOS)
        options.appearance = NSAppearance(named: .aqua)
        #else
        options.traitCollection = UITraitCollection(displayScale: 1)
        #endif
        let snapshot = try await MKMapSnapshotter(options: options).start()

        let imageFile = "\(row.parkID)\(scale.suffix).png"
        try write(snapshot.image, to: directory.appendingPathComponent(imageFile))

        var maskFile: String?
        let traced = row.cables.filter { $0.geometry.pointsXY.count >= 2 }
        if !traced.isEmpty {
            let projection = LocalProjection(origin: row.location)
            let polylines: [(points: [CGPoint], closed: Bool)] = traced.map { cable in
                let points = cable.geometry.pointsXY.map { xy -> CGPoint in
                    let coordinate = projection.coordinate(xy)
                    return snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon))
                }
                return (points, cable.geometry.isClosed)
            }
            maskFile = "\(row.parkID)\(scale.suffix)-mask.png"
            try write(mask(size: options.size, polylines: polylines), to: directory.appendingPathComponent(maskFile!))
        }

        return TrainingRow.Snapshot(
            imageFile: imageFile,
            maskFile: maskFile,
            sizePx: scale.sizePx,
            metersPerPixel: scale.metersPerPixel,
            center: center
        )
    }

    /// White cables on black. `snapshot.point(for:)` is in the platform image's own coordinate
    /// space (bottom-left on macOS, top-left on iOS), so each branch draws in that same space.
    private static func mask(size: CGSize, polylines: [(points: [CGPoint], closed: Bool)]) -> PlatformImage {
        func stroke(in context: CGContext) {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(6)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for polyline in polylines where polyline.points.count >= 2 {
                context.addLines(between: polyline.points)
                if polyline.closed { context.closePath() }
                context.strokePath()
            }
        }
        #if os(macOS)
        return NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            stroke(in: context)
            return true
        }
        #else
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in stroke(in: renderer.cgContext) }
        #endif
    }

    private static func write(_ image: PlatformImage, to url: URL) throws {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        #else
        guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        #endif
        try png.write(to: url)
    }
}

#if os(macOS)
public typealias PlatformImage = NSImage
#else
public typealias PlatformImage = UIImage
#endif
