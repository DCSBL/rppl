import MapKit
import RpplCore
import SwiftUI

/// Full-screen map to trace a cable: pan/zoom so the center marker sits on the spot, then press Add point.
/// Tap an existing point to select it, pan to the new spot and press Move here.
struct CableTraceView: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    /// Point marker; the selected one and the start flag inside it scale along with it.
    @ScaledMetric(relativeTo: .caption2) private var markerSize: CGFloat = 14
    @Binding var cable: ParkCable
    let center: ParkCoordinate
    /// The park's other cables: drawn for orientation.
    let otherCables: [ParkCable]

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?
    @State private var position: MapCameraPosition
    @State private var viewCenter: CLLocationCoordinate2D
    @State private var askShape = false
    @State private var showLegend = false

    init(cable: Binding<ParkCable>, center: ParkCoordinate, otherCables: [ParkCable] = []) {
        _cable = cable
        self.center = center
        self.otherCables = otherCables
        let anchor = cable.wrappedValue.points?.first?.coordinate ?? center
        let start = CLLocationCoordinate2D(latitude: anchor.lat, longitude: anchor.lon)
        _viewCenter = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )))
    }

    private var points: [ParkCablePoint] { cable.points ?? [] }

    private func coordinate(_ point: ParkCablePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    private var centerCoordinate: ParkCoordinate {
        ParkCoordinate(lat: viewCenter.latitude, lon: viewCenter.longitude)
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(Array(otherCables.enumerated()), id: \.offset) { _, other in
                    if let line = other.points?.map(coordinate), line.count >= 2 {
                        MapPolyline(coordinates: other.direction?.isLoop == true ? line + [line[0]] : line)
                            .stroke(Color.rpplMuted.opacity(0.8), lineWidth: 2)
                    }
                }
                if points.count >= 2 {
                    let line = points.map(coordinate)
                    MapPolyline(coordinates: cable.direction?.isLoop == true ? line + [line[0]] : line)
                        .stroke(Color.rpplAccent, lineWidth: 3)
                }
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Annotation("", coordinate: coordinate(point), anchor: .center) {
                        pointMarker(index: index, point: point)
                    }
                }
            }
            .mapStyle(usesSatellite ? .hybrid(elevation: .flat) : .standard)
            .onMapCameraChange(frequency: .continuous) { context in
                viewCenter = context.camera.centerCoordinate
            }
            .overlay { MapCrosshair() }
            .overlay(alignment: .topLeading) {
                if showLegend {
                    CableTraceLegend(showsOtherCables: !otherCables.isEmpty)
                        .padding(12)
                }
            }
            .safeAreaInset(edge: .bottom) {
                controls
            }
            .navigationTitle("Trace cable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Only ask what kind of cable it is when that is not known yet.
                    Button("Done") { points.count >= 2 && cable.direction == nil ? (askShape = true) : dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        usesSatellite.toggle()
                    } label: {
                        Image(systemName: usesSatellite ? "map" : "globe.europe.africa")
                    }
                    .accessibilityLabel(Text("Map style"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLegend.toggle()
                    } label: {
                        Image(systemName: showLegend ? "info.circle.fill" : "info.circle")
                    }
                    .accessibilityLabel(Text("Legend"))
                }
            }
            .alert("Is this cable a full-size loop or 2.0?", isPresented: $askShape) {
                Button("Full size (loop)") {
                    // Points are in travel order, so the winding of the trace is the direction riders go.
                    cable.direction = cable.tracedWindingIsClockwise == false ? .counterClockwise : .clockwise
                    dismiss()
                }
                Button("2.0 (back and forth)") {
                    cable.direction = .twoPointZero
                    dismiss()
                }
                Button("Keep tracing", role: .cancel) {}
            }
        }
    }

    private func pointMarker(index: Int, point: ParkCablePoint) -> some View {
        let isSelected = selected == index
        return Button {
            selected = isSelected ? nil : index
        } label: {
            Circle()
                .fill(point.start == true ? Color.green : (isSelected ? Color.orange : Color.rpplAccent))
                .frame(width: isSelected ? markerSize * 1.6 : markerSize, height: isSelected ? markerSize * 1.6 : markerSize)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .overlay {
                    if differentiateWithoutColor, point.start == true {
                        Image(systemName: "flag.fill")
                            .font(.system(size: markerSize * 0.6))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: max(44, markerSize * 2), height: max(44, markerSize * 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Point \(index + 1)"))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                if let symbol = directionSymbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Color.rpplAccent)
                        .accessibilityLabel(Text(directionName))
                }
                Text(lengthText).font(.subheadline.weight(.semibold))
                Spacer()
                Button("Reverse direction", systemImage: "arrow.left.arrow.right") {
                    ParkDraft.reverse(&cable)
                    selected = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(points.count < 2)
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    ParkDraft.undo(&cable)
                    selected = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(points.isEmpty)
            }
            centerLine
            if let index = selected {
                HStack {
                    Button("Move here", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                        ParkDraft.move(&cable, index: index, to: centerCoordinate)
                        selected = nil
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Start", systemImage: "flag") { ParkDraft.toggleStart(&cable, index: index) }
                        .buttonStyle(.bordered)
                    Button("Delete point", systemImage: "trash", role: .destructive) {
                        ParkDraft.remove(&cable, index: index)
                        selected = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    ParkDraft.append(centerCoordinate, to: &cable)
                } label: {
                    Label("Add point", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("Pan and zoom until the marker is on the cable, then add the point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }

    /// Where the marker is, and how far that is from the park pin, so the reviewer can tell where on the
    /// map the route sits; the menu jumps back to the pin or to the traced points.
    private var centerLine: some View {
        HStack(spacing: 8) {
            Text(verbatim: String(format: "%.5f, %.5f", viewCenter.latitude, viewCenter.longitude))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(distanceToPinText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Park pin", systemImage: "mappin") { show(center) }
                if !points.isEmpty {
                    Button("Traced points", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { showTrace() }
                }
            } label: {
                Label("Go to", systemImage: "location.viewfinder")
                    .font(.caption)
            }
        }
    }

    private var distanceToPinText: String {
        let meters = centerCoordinate.meters(to: center)
        return meters < 1000
            ? String(localized: "\(Int(meters.rounded())) m from the pin")
            : String(localized: "\(String(format: "%.1f", meters / 1000)) km from the pin")
    }

    private var directionSymbol: String? {
        switch cable.direction {
        case .clockwise?: "arrow.clockwise"
        case .counterClockwise?: "arrow.counterclockwise"
        case .twoPointZero?: "arrow.left.and.right"
        default: nil
        }
    }

    private var directionName: String {
        switch cable.direction {
        case .clockwise?: String(localized: "Clockwise")
        case .counterClockwise?: String(localized: "Counter-clockwise")
        case .twoPointZero?: String(localized: "2.0")
        default: ""
        }
    }

    private func show(_ coordinate: ParkCoordinate) {
        position = .region(MKCoordinateRegion(center: mapCoordinate(coordinate), latitudinalMeters: 600, longitudinalMeters: 600))
    }

    private func showTrace() {
        show(points.map(\.coordinate))
    }

    private func show(_ coordinates: [ParkCoordinate]) {
        let lats = coordinates.map(\.lat), lons = coordinates.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.002, (maxLat - minLat) * 1.6), longitudeDelta: max(0.002, (maxLon - minLon) * 1.6))
        ))
    }

    private func mapCoordinate(_ coordinate: ParkCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
    }

    private var lengthText: String {
        guard let length = cable.computedLengthM else { return String(localized: "\(points.count) points") }
        return String(localized: "\(points.count) points · \(Int(length.rounded())) m")
    }
}

/// What the colours on the trace map mean.
struct CableTraceLegend: View {
    var showsOtherCables: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row { line(Color.rpplAccent, width: 3) } text: { Text("This cable, in riding order") }
            row { dot(Color.green) } text: { Text("Start point") }
            row { dot(Color.orange) } text: { Text("Selected point") }
            if showsOtherCables {
                row { line(Color.rpplMuted, width: 2) } text: { Text("Other cables of this park") }
            }
            row {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 1.5).frame(width: 14, height: 14)
                    Circle().fill(Color.rpplAccent).frame(width: 5, height: 5)
                }
                .shadow(radius: 1)
            } text: {
                Text("Map centre: points go here")
            }
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 260, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(@ViewBuilder symbol: () -> some View, @ViewBuilder text: () -> Text) -> some View {
        HStack(spacing: 8) {
            symbol().frame(width: 22, height: 14)
            text().foregroundStyle(.primary)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 10, height: 10).overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
    }

    private func line(_ color: Color, width: CGFloat, dash: [CGFloat] = []) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 7))
            path.addLine(to: CGPoint(x: 22, y: 7))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }
}
