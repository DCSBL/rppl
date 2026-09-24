import MapKit
import RpplCore
import SwiftUI

/// Full-screen map to trace a cable: tap to add points, tap a point to select it, then tap the map to move it.
struct CableTraceView: View {
    @Binding var cable: ParkCable
    let center: ParkCoordinate

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?
    @State private var position: MapCameraPosition

    init(cable: Binding<ParkCable>, center: ParkCoordinate) {
        _cable = cable
        self.center = center
        let anchor = cable.wrappedValue.points?.first?.coordinate ?? center
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: anchor.lat, longitude: anchor.lon),
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )))
    }

    private var points: [ParkCablePoint] { cable.points ?? [] }

    private func coordinate(_ point: ParkCablePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
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
                .onTapGesture { screen in
                    guard let tapped = proxy.convert(screen, from: .local) else { return }
                    let coordinate = ParkCoordinate(lat: tapped.latitude, lon: tapped.longitude)
                    if let index = selected {
                        ParkDraft.move(&cable, index: index, to: coordinate)
                        selected = nil
                    } else {
                        ParkDraft.append(coordinate, to: &cable)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("Trace cable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
        }
    }

    private func pointMarker(index: Int, point: ParkCablePoint) -> some View {
        let isSelected = selected == index
        return Button {
            selected = isSelected ? nil : index
        } label: {
            Circle()
                .fill(point.start == true ? Color.green : Color.rpplAccent)
                .frame(width: isSelected ? 22 : 14, height: isSelected ? 22 : 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Point \(index + 1)"))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(lengthText).font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Direction", selection: directionBinding) {
                    Text("Clockwise").tag("cw")
                    Text("Counter-clockwise").tag("ccw")
                    Text("2D").tag("2d")
                }
                .pickerStyle(.menu)
            }
            Text(selected == nil ? "Tap the map to add points along the cable." : "Tap the map to move the selected point.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    ParkDraft.undo(&cable)
                    selected = nil
                }
                .disabled(points.isEmpty)
                Button("Clear", systemImage: "trash", role: .destructive) {
                    cable.points = nil
                    selected = nil
                }
                .disabled(points.isEmpty)
                Spacer()
                if let index = selected {
                    Button("Start", systemImage: "flag") {
                        ParkDraft.toggleStart(&cable, index: index)
                    }
                    Button("Delete point", systemImage: "minus.circle", role: .destructive) {
                        ParkDraft.remove(&cable, index: index)
                        selected = nil
                    }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var directionBinding: Binding<String> {
        Binding(
            get: { cable.direction?.rawValue ?? "cw" },
            set: { cable.direction = ParkCableDirection(rawValue: $0) }
        )
    }

    private var lengthText: String {
        guard let length = cable.computedLengthM else { return String(localized: "\(points.count) points") }
        return String(localized: "\(points.count) points · \(Int(length.rounded())) m")
    }
}
