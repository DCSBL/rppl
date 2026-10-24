import MapKit
import SwiftUI

/// The heading of a full-screen map, for the app's own compass (the `custom…` layouts of
/// `MapCompassLayout`). The map reports its camera through `mapScreenControls(scope:position:)`; a tap
/// on the compass asks the map to point north again.
@Observable
final class MapScreenCompass {
    /// Degrees clockwise from north, 0..<360.
    private(set) var heading: Double = 0
    @ObservationIgnored private(set) var camera: MapCamera?
    /// Bumped by `pointNorth()`; the map turns north on each change.
    private(set) var northRequests = 0
    /// Turned more than a degree away from north; MapKit's compass shows from then on, too. Stored, so
    /// views that only show or hide the compass don't follow every degree.
    private(set) var isRotated = false

    func update(_ camera: MapCamera) {
        self.camera = camera
        let normalized = camera.heading.truncatingRemainder(dividingBy: 360)
        let newHeading = normalized < 0 ? normalized + 360 : normalized
        if abs(newHeading - heading) > 0.1 {
            heading = newHeading
        }
        let rotated = min(newHeading, 360 - newHeading) > 1
        if rotated != isRotated {
            isRotated = rotated
        }
    }

    func pointNorth() {
        northRequests += 1
    }

    /// The current camera turned north, or nil before the map reported one.
    var northCamera: MapCamera? {
        guard let camera else { return nil }
        return MapCamera(
            centerCoordinate: camera.centerCoordinate,
            distance: camera.distance,
            heading: 0,
            pitch: camera.pitch
        )
    }
}

/// A dial like MapKit's compass: ticks, a red marker and N, turning with the map. Tap points north.
struct MapScreenCompassDial: View {
    let compass: MapScreenCompass
    /// Its own glass circle; off inside a bar item, which brings its own.
    var hasGlass = true

    static let size: CGFloat = 44

    var body: some View {
        Button { compass.pointNorth() } label: {
            face
                .frame(width: Self.size, height: Self.size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(CompassGlass(isOn: hasGlass))
        .accessibilityLabel(Text(verbatim: "Compass, point north"))
    }

    private var face: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { tick in
                Capsule()
                    .fill(tick == 0 ? Color.clear : Color.secondary)
                    .frame(width: 1.5, height: tick.isMultiple(of: 3) ? 5 : 3)
                    .offset(y: -Self.size / 2 + 6)
                    .rotationEffect(.degrees(Double(tick) * 30))
            }
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 7))
                .foregroundStyle(.red)
                .offset(y: -Self.size / 2 + 7)
            Text(verbatim: "N")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .rotationEffect(.degrees(-compass.heading))
    }
}

private struct CompassGlass: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}

/// A bar button whose north arrow turns with the map. Tap points north.
struct MapScreenNorthButton: View {
    let compass: MapScreenCompass

    var body: some View {
        Button { compass.pointNorth() } label: {
            Image(systemName: "location.north.line")
                .rotationEffect(.degrees(-compass.heading))
        }
        .accessibilityLabel(Text(verbatim: "Point north"))
    }
}
