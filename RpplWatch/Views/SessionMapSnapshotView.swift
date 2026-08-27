import SwiftUI
import MapKit
import RpplCore
import WatchKit
import UIKit

/// Static map thumbnail for Watch — SwiftUI `Map` often renders blank in small/scroll layouts.
enum SessionMapSnapshotSource: Equatable, Sendable {
    case coordinate(CLLocationCoordinate2D, distanceMeters: CLLocationDistance)
    case frame(MapTrackFrame)

    var cacheKey: String {
        switch self {
        case let .coordinate(coordinate, distanceMeters):
            return "c:\(coordinate.latitude),\(coordinate.longitude):\(distanceMeters)"
        case let .frame(frame):
            return "f:\(frame.centerLatitude),\(frame.centerLongitude):\(frame.spanWidthMeters):\(frame.spanHeightMeters)"
        }
    }
}

enum SessionMapSnapshotRenderer {
    static func render(
        source: SessionMapSnapshotSource,
        size: CGSize,
        scale: CGFloat,
        showsPin: Bool
    ) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = scale
        options.mapType = .standard

        let pinCoordinate: CLLocationCoordinate2D
        switch source {
        case let .coordinate(coordinate, distanceMeters):
            pinCoordinate = coordinate
            options.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: distanceMeters * 2,
                longitudinalMeters: distanceMeters * 2
            )
        case let .frame(frame):
            pinCoordinate = CLLocationCoordinate2D(
                latitude: frame.centerLatitude,
                longitude: frame.centerLongitude
            )
            options.region = MKCoordinateRegion(
                center: pinCoordinate,
                latitudinalMeters: max(frame.spanHeightMeters, 120),
                longitudinalMeters: max(frame.spanWidthMeters, 120)
            )
        }

        let snapshot = try await MKMapSnapshotter(options: options).start()
        guard showsPin else { return snapshot.image }
        return drawPin(on: snapshot, coordinate: pinCoordinate)
    }

    private static func drawPin(
        on snapshot: MKMapSnapshotter.Snapshot,
        coordinate: CLLocationCoordinate2D
    ) -> UIImage {
        let base = snapshot.image
        let point = snapshot.point(for: coordinate)
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: base.size, format: format).image { _ in
            base.draw(at: .zero)
            let pinDiameter: CGFloat = 10
            let pinRect = CGRect(
                x: point.x - pinDiameter / 2,
                y: point.y - pinDiameter,
                width: pinDiameter,
                height: pinDiameter
            )
            UIColor.systemRed.setFill()
            UIBezierPath(ovalIn: pinRect).fill()
            UIColor.white.setStroke()
            UIBezierPath(ovalIn: pinRect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }
}

struct SessionMapSnapshotView: View {
    let source: SessionMapSnapshotSource
    var size: CGSize
    var cornerRadius: CGFloat = 10
    var showsPin: Bool = true

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        if loadFailed {
                            Image(systemName: "map")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(String(localized: "Session start location"))
        .task(id: taskKey) {
            await loadSnapshot()
        }
    }

    private var taskKey: String {
        "\(source.cacheKey)|\(size.width)x\(size.height)|pin:\(showsPin)"
    }

    private func loadSnapshot() async {
        image = nil
        loadFailed = false
        guard size.width >= 1, size.height >= 1 else {
            loadFailed = true
            return
        }
        do {
            let scale = WKInterfaceDevice.current().screenScale
            let rendered = try await SessionMapSnapshotRenderer.render(
                source: source,
                size: size,
                scale: scale,
                showsPin: showsPin
            )
            image = rendered
        } catch {
            WakeLog.error(.ui, "SessionMapSnapshot failed: \(error.localizedDescription)")
            loadFailed = true
        }
    }
}
