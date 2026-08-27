import SwiftUI
import MapKit
import RpplCore
import WatchKit

/// Static map thumbnail for Watch — SwiftUI `Map` often renders blank in small/scroll layouts.
enum SessionMapSnapshotSource: Sendable {
    case coordinate(CLLocationCoordinate2D, distanceMeters: CLLocationDistance)
    case frame(MapTrackFrame)
    case sessionTracks(SessionMapTrackData, style: SessionMapTrackStyle, frame: MapTrackFrame?)

    var cacheKey: String {
        switch self {
        case let .coordinate(coordinate, distanceMeters):
            return "c:\(coordinate.latitude),\(coordinate.longitude):\(distanceMeters)"
        case let .frame(frame):
            return "f:\(frame.centerLatitude),\(frame.centerLongitude):\(frame.spanWidthMeters):\(frame.spanHeightMeters)"
        case let .sessionTracks(data, style, frame):
            let frameKey = frame.map {
                "\($0.centerLatitude),\($0.centerLongitude),\($0.spanWidthMeters)"
            } ?? "nil"
            return "t:\(style.rawValue):\(data.averagedTrack.count):\(data.heatmapTracks.count):\(frameKey)"
        }
    }

    static func sessionMap(
        mapTracks: SessionMapTrackData?,
        trackStyle: SessionMapTrackStyle,
        startCoordinate: CLLocationCoordinate2D?,
        mapFrame: MapTrackFrame?,
        startDistanceMeters: CLLocationDistance = 500
    ) -> SessionMapSnapshotSource? {
        if let mapTracks, mapTracks.hasRenderableTrack {
            return .sessionTracks(mapTracks, style: trackStyle, frame: mapFrame)
        }
        if let startCoordinate {
            return .coordinate(startCoordinate, distanceMeters: startDistanceMeters)
        }
        if let mapFrame {
            return .frame(mapFrame)
        }
        return nil
    }
}

enum SessionMapSnapshotRenderer {
    private static let trackStrokeColor = UIColor(red: 0.18, green: 0.78, blue: 0.71, alpha: 1)
    private static let startPinColor = UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)

    static func render(
        source: SessionMapSnapshotSource,
        size: CGSize,
        scale: CGFloat
    ) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = scale

        switch source {
        case let .coordinate(coordinate, distanceMeters):
            options.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: distanceMeters * 2,
                longitudinalMeters: distanceMeters * 2
            )
        case let .frame(frame):
            let center = CLLocationCoordinate2D(
                latitude: frame.centerLatitude,
                longitude: frame.centerLongitude
            )
            options.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: max(frame.spanHeightMeters, 120),
                longitudinalMeters: max(frame.spanWidthMeters, 120)
            )
        case let .sessionTracks(data, _, frame):
            if let frame {
                let center = CLLocationCoordinate2D(
                    latitude: frame.centerLatitude,
                    longitude: frame.centerLongitude
                )
                options.region = MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: max(frame.spanHeightMeters, 120),
                    longitudinalMeters: max(frame.spanWidthMeters, 120)
                )
            } else {
                options.region = region(for: data, paddingFactor: 1.25)
            }
        }

        let snapshot = try await MKMapSnapshotter(options: options).start()
        switch source {
        case .coordinate, .frame:
            return snapshot.image
        case let .sessionTracks(data, style, _):
            return drawTracks(on: snapshot, data: data, style: style)
        }
    }

    private static func region(for data: SessionMapTrackData, paddingFactor: Double) -> MKCoordinateRegion {
        let coords = data.averagedTrack.count >= 2
            ? data.averagedTrack
            : data.heatmapTracks.flatMap { $0 }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? data.start.latitude
        let maxLat = lats.max() ?? data.start.latitude
        let minLon = lons.min() ?? data.start.longitude
        let maxLon = lons.max() ?? data.start.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latMeters = max((maxLat - minLat) * 111_000 * paddingFactor, 120)
        let lonMeters = max((maxLon - minLon) * 111_000 * cos(center.latitude * .pi / 180) * paddingFactor, 120)
        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: latMeters,
            longitudinalMeters: lonMeters
        )
    }

    private static func drawTracks(
        on snapshot: MKMapSnapshotter.Snapshot,
        data: SessionMapTrackData,
        style: SessionMapTrackStyle
    ) -> UIImage {
        let image = snapshot.image
        UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
        image.draw(at: .zero)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return image
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch style {
        case .averaged:
            if let speeds = data.averagedSpeedKmh,
               let segments = SessionMapSpeedColor.segments(track: data.averagedTrack, speedsKmh: speeds) {
                for segment in segments where segment.coordinates.count >= 2 {
                    let uiColor = UIColor(
                        red: segment.color.red,
                        green: segment.color.green,
                        blue: segment.color.blue,
                        alpha: 1
                    )
                    stroke(
                        context: context,
                        snapshot: snapshot,
                        coordinates: segment.coordinates,
                        color: uiColor,
                        lineWidth: max(2, image.size.width * 0.018)
                    )
                }
            } else {
                stroke(
                    context: context,
                    snapshot: snapshot,
                    coordinates: data.averagedTrack,
                    color: trackStrokeColor,
                    lineWidth: max(2, image.size.width * 0.018)
                )
            }
        case .heatmap:
            let opacity = min(0.35, 0.85 / Double(max(data.heatmapTracks.count, 1)))
            let lineWidth = max(2.5, image.size.width * 0.022)
            for track in data.heatmapTracks where track.count >= 2 {
                stroke(
                    context: context,
                    snapshot: snapshot,
                    coordinates: track,
                    color: trackStrokeColor.withAlphaComponent(opacity),
                    lineWidth: lineWidth
                )
            }
        }

        drawStartPin(context: context, snapshot: snapshot, coordinate: data.start)
        let composed = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return composed
    }

    private static func stroke(
        context: CGContext,
        snapshot: MKMapSnapshotter.Snapshot,
        coordinates: [MapCoordinate],
        color: UIColor,
        lineWidth: CGFloat
    ) {
        guard coordinates.count >= 2 else { return }
        context.beginPath()
        var started = false
        for coordinate in coordinates {
            let point = snapshot.point(for: CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
            if !started {
                context.move(to: point)
                started = true
            } else {
                context.addLine(to: point)
            }
        }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }

    private static func drawStartPin(
        context: CGContext,
        snapshot: MKMapSnapshotter.Snapshot,
        coordinate: MapCoordinate
    ) {
        let point = snapshot.point(for: CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
        let radius = max(3, snapshot.image.size.width * 0.012)
        context.setFillColor(startPinColor.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
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
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    if showsPin {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                    }
                }
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
        .accessibilityLabel(String(localized: "Session map"))
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
            image = try await SessionMapSnapshotRenderer.render(
                source: source,
                size: size,
                scale: scale
            )
        } catch {
            WakeLog.error(.ui, "SessionMapSnapshot failed: \(error.localizedDescription)")
            loadFailed = true
        }
    }
}
