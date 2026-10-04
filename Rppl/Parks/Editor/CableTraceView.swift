import MapKit
import RpplCore
import SwiftUI

/// Full-screen map to trace a cable: pan/zoom so the center marker sits on the spot, then press Add point.
/// Tap an existing point to select it, pan to the new spot and press Move here.
struct CableTraceView: View {
    @Binding var cable: ParkCable
    let center: ParkCoordinate

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?
    @State private var position: MapCameraPosition
    @State private var viewCenter: CLLocationCoordinate2D
    @State private var askShape = false

    init(cable: Binding<ParkCable>, center: ParkCoordinate) {
        _cable = cable
        self.center = center
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
            .safeAreaInset(edge: .bottom) { controls }
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
            }
            .alert("Is this cable a full-size loop or 2D?", isPresented: $askShape) {
                Button("Full size (loop)") {
                    // Points are in travel order, so the winding of the trace is the direction riders go.
                    cable.direction = cable.tracedWindingIsClockwise == false ? .counterClockwise : .clockwise
                    dismiss()
                }
                Button("2D (back and forth)") {
                    cable.direction = .twoD
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
                .frame(width: isSelected ? 22 : 14, height: isSelected ? 22 : 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Point \(index + 1)"))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(lengthText).font(.subheadline.weight(.semibold))
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    ParkDraft.undo(&cable)
                    selected = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(points.isEmpty)
            }
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

    private var lengthText: String {
        guard let length = cable.computedLengthM else { return String(localized: "\(points.count) points") }
        return String(localized: "\(points.count) points · \(Int(length.rounded())) m")
    }
}
