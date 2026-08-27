import SwiftUI
import MapKit
import RpplCore
import WatchKit

/// Static map thumbnail for Watch — SwiftUI `Map` often renders blank in small/scroll layouts.
enum SessionMapSnapshotSource: Sendable {
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
        }

        return try await MKMapSnapshotter(options: options).start().image
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
