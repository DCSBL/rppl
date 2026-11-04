import MapKit
import RpplCore
import UIKit

/// Takes a satellite close-up of the park with MapKit and runs the cable detector on it.
/// The image never leaves the device; only the Debug tower review keeps it, for the
/// detector's training set (see `TowerReviewStore`).
enum CableDetectionRunner {
    /// Side of the close-up in metres; the cable is never further than ~500 m from the park pin.
    static let sideMeters = 600.0
    /// Pixels per side: 0.29 m/px, the scale the detector was tuned on.
    static let sidePixels = 2048

    struct Outcome: Sendable {
        var image: DetectionImage
        var result: CableDetectionResult
        var snapshotSeconds: TimeInterval
    }

    enum Failure: LocalizedError {
        case noImage

        var errorDescription: String? {
            switch self {
            case .noImage: String(localized: "No satellite image for this spot.")
            }
        }
    }

    /// `avoiding` are the park's other cables: the proposal stays clear of the ones on the image.
    static func detect(around center: ParkCoordinate, avoiding others: [ParkCable] = []) async throws -> Outcome {
        let started = Date()
        let image = try await snapshot(around: center)
        let snapshotSeconds = Date().timeIntervalSince(started)
        let result = await Task.detached(priority: .userInitiated) {
            var options = CableDetector.Options()
            options.occupied = CableDetector.occupiedPolylines(of: others, in: image)
            return CableDetector.detect(in: image, options: options)
        }.value
        return Outcome(image: image, result: result, snapshotSeconds: snapshotSeconds)
    }

    @MainActor
    static func snapshot(around center: ParkCoordinate) async throws -> DetectionImage {
        let options = MKMapSnapshotter.Options()
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon),
            latitudinalMeters: sideMeters,
            longitudinalMeters: sideMeters
        )
        options.size = CGSize(width: sidePixels / 2, height: sidePixels / 2)
        options.scale = 2
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        let snapshot = try await MKMapSnapshotter(options: options).start()
        guard let cgImage = snapshot.image.cgImage else { throw Failure.noImage }
        let width = cgImage.width, height = cgImage.height
        // Draw into a plain RGBX buffer, then drop the padding byte.
        var rgbx = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgbx.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw Failure.noImage }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            rgb[index * 3] = rgbx[index * 4]
            rgb[index * 3 + 1] = rgbx[index * 4 + 1]
            rgb[index * 3 + 2] = rgbx[index * 4 + 2]
        }
        // Scale and centre from the snapshot's own projection, so a region MapKit adjusted still maps right.
        let pixelScale = Double(width) / Double(snapshot.image.size.width)
        let pin = snapshot.point(for: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon))
        let east = DetectionImage.coordinate(fromLocal: SIMD2(100, 0), origin: center)
        let eastPoint = snapshot.point(for: CLLocationCoordinate2D(latitude: east.lat, longitude: east.lon))
        let metersPerPixel = 100 / max(1, Double(eastPoint.x - pin.x) * pixelScale)
        let centerXY = SIMD2(
            (Double(width) / 2 - Double(pin.x) * pixelScale) * metersPerPixel,
            (Double(pin.y) * pixelScale - Double(height) / 2) * metersPerPixel
        )
        var image = DetectionImage(
            width: width,
            height: height,
            rgb: rgb,
            metersPerPixel: metersPerPixel,
            center: DetectionImage.coordinate(fromLocal: centerXY, origin: center),
            origin: center
        )
        // A 3 x 3 grid of known coordinates with the pixel MapKit put each at, so the frame can be
        // checked against MapKit itself later (the tower review saves them with the image).
        image.controlPoints = [-250.0, 0, 250].flatMap { north in
            [-250.0, 0, 250].map { east in
                let coordinate = DetectionImage.coordinate(fromLocal: SIMD2(east, north), origin: center)
                let point = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon))
                return DetectionImage.ControlPoint(coordinate: coordinate, column: Double(point.x) * pixelScale, row: Double(point.y) * pixelScale)
            }
        }
        return image
    }
}
