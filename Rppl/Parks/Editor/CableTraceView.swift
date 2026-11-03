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
    /// The park's other cables: drawn for orientation and kept clear of by the detector.
    let otherCables: [ParkCable]

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?
    @State private var position: MapCameraPosition
    @State private var viewCenter: CLLocationCoordinate2D
    @State private var askShape = false
    @AppStorage(AppSettingsKey.debugCableDetection) private var detectionEnabled = false
    @State private var detecting = false
    @State private var detection: CableDetectionRunner.Outcome?
    @State private var detectionError: String?
    @State private var askProposalDirection = false
    @State private var confirmReplaceByProposal = false
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
                if let detection {
                    if let proposal = detection.result.best {
                        let line = proposal.vertices.map { mapCoordinate(detection.image.coordinate(fromLocal: $0)) }
                        MapPolyline(coordinates: line + [line[0]])
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                    }
                    ForEach(Array(detection.result.towers.enumerated()), id: \.offset) { _, tower in
                        Annotation("", coordinate: mapCoordinate(detection.image.coordinate(fromLocal: tower.xy)), anchor: .center) {
                            Circle()
                                .fill(Color.purple.opacity(0.4 + 0.6 * tower.probability))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        }
                    }
                }
            }
            .mapStyle(usesSatellite ? .hybrid(elevation: .flat) : .standard)
            .onMapCameraChange(frequency: .continuous) { context in
                viewCenter = context.camera.centerCoordinate
            }
            .overlay { MapCrosshair() }
            .overlay(alignment: .top) {
                if detecting {
                    ProgressView("Looking for the cable…")
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 12)
                }
            }
            .overlay(alignment: .topLeading) {
                if showLegend {
                    CableTraceLegend(showsDetection: detectionEnabled, showsOtherCables: !otherCables.isEmpty)
                        .padding(12)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if detection != nil { proposalControls } else { controls }
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
                if detectionEnabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            detectCable()
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .disabled(detecting)
                        .accessibilityLabel(Text("Detect cable"))
                    }
                }
            }
            .sheet(isPresented: $askProposalDirection) {
                CableDirectionSheet(
                    title: String(localized: "Which way do riders go on this cable?"),
                    message: String(localized: "The proposal is a starting point: check every tower against the imagery and move the points that are off. Reverse later with the arrows button if you pick wrong.")
                ) { direction in
                    askProposalDirection = false
                    applyProposal(direction: direction)
                }
            }
            .alert("Replace the traced points?", isPresented: $confirmReplaceByProposal) {
                Button("Replace", role: .destructive) { askProposalDirection = true }
                Button("Keep mine", role: .cancel) {}
            } message: {
                Text("The points you traced go away; the proposal takes their place.")
            }
            .alert("Detection failed", isPresented: Binding(get: { detectionError != nil }, set: { if !$0 { detectionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(detectionError ?? "")
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
                Text(detectionEnabled
                    ? String(localized: "Pan and zoom until the marker is on the cable, then add the point. Detection looks 300 m around the marker.")
                    : String(localized: "Pan and zoom until the marker is on the cable, then add the point."))
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
                if let detection, let best = detection.result.best {
                    Button("Proposal", systemImage: "sparkles") { show(best, in: detection.image) }
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

    private func show(_ candidate: CableLoopCandidate, in image: DetectionImage) {
        show(candidate.vertices.map { image.coordinate(fromLocal: $0) })
    }

    private func show(_ coordinates: [ParkCoordinate]) {
        let lats = coordinates.map(\.lat), lons = coordinates.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.002, (maxLat - minLat) * 1.6), longitudeDelta: max(0.002, (maxLon - minLon) * 1.6))
        ))
    }

    // MARK: Detection

    private func mapCoordinate(_ coordinate: ParkCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
    }

    private func detectCable() {
        guard !detecting else { return }
        detecting = true
        detection = nil
        selected = nil
        Task {
            defer { detecting = false }
            do {
                // Look around the marker, not the park pin: zoom in on a lake to pick one of several cables.
                let outcome = try await CableDetectionRunner.detect(around: centerCoordinate, avoiding: otherCables)
                detection = outcome
                showLegend = true
                if let best = outcome.result.best { show(best, in: outcome.image) }
            } catch {
                detectionError = error.localizedDescription
            }
        }
    }

    private func applyProposal(direction: ParkCableDirection) {
        guard let detection, let best = detection.result.best else { return }
        let proposed = CableDetector.cable(from: best, in: detection.image, direction: direction)
        cable.points = proposed.points
        cable.direction = direction
        self.detection = nil
        selected = nil
    }

    private var proposalControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let detection {
                if let best = detection.result.best {
                    Label {
                        Text(proposalSummary(best, outcome: detection))
                    } icon: {
                        Image(systemName: best.isWeak ? "exclamationmark.triangle" : "sparkles")
                            .foregroundStyle(best.isWeak ? Color.orange : Color.purple)
                    }
                    .font(.subheadline)
                    HStack {
                        Button {
                            if points.isEmpty { askProposalDirection = true } else { confirmReplaceByProposal = true }
                        } label: {
                            Label("Use proposal", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Dismiss") { self.detection = nil }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Label(detection.result.notes.last ?? String(localized: "No cable found on the imagery."), systemImage: "questionmark.circle")
                        .font(.subheadline)
                    Button("Dismiss") { self.detection = nil }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private func proposalSummary(_ best: CableLoopCandidate, outcome: CableDetectionRunner.Outcome) -> String {
        var parts: [String] = [
            String(localized: "\(best.vertices.count) towers · \(Int(best.perimeterM.rounded())) m"),
        ]
        if best.isWeak { parts.append(String(localized: "weak match, check closely")) }
        if !best.notes.isEmpty { parts.append(best.notes.joined(separator: ", ")) }
        let seconds = String(format: "%.1f", outcome.snapshotSeconds + outcome.result.elapsed)
        parts.append(String(localized: "\(outcome.result.towers.count) tower hits, \(outcome.result.objects.count) objects, \(seconds) s"))
        return parts.joined(separator: " · ")
    }

    private var lengthText: String {
        guard let length = cable.computedLengthM else { return String(localized: "\(points.count) points") }
        return String(localized: "\(points.count) points · \(Int(length.rounded())) m")
    }
}

/// What the colours on the trace map mean.
struct CableTraceLegend: View {
    var showsDetection: Bool
    var showsOtherCables: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row { line(Color.rpplAccent, width: 3) } text: { Text("This cable, in riding order") }
            row { dot(Color.green) } text: { Text("Start point") }
            row { dot(Color.orange) } text: { Text("Selected point") }
            if showsOtherCables {
                row { line(Color.rpplMuted, width: 2) } text: { Text("Other cables of this park") }
            }
            if showsDetection {
                row { line(Color.purple, width: 3, dash: [4, 3]) } text: { Text("Proposal from the imagery") }
                row { dot(Color.purple) } text: { Text("Detected tower") }
            }
            row {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 1.5).frame(width: 14, height: 14)
                    Circle().fill(Color.rpplAccent).frame(width: 5, height: 5)
                }
                .shadow(radius: 1)
            } text: {
                Text(showsDetection ? "Map centre: points go here, detection looks around it" : "Map centre: points go here")
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

/// Clockwise or counter-clockwise, with the arrow next to the words.
struct CableDirectionSheet: View {
    var title: String
    var message: String
    var pick: (ParkCableDirection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                choice(.clockwise, name: String(localized: "Clockwise"), symbol: "arrow.clockwise")
                choice(.counterClockwise, name: String(localized: "Counter-clockwise"), symbol: "arrow.counterclockwise")
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func choice(_ direction: ParkCableDirection, name: String, symbol: String) -> some View {
        Button {
            pick(direction)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 36, weight: .semibold))
                Text(name).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.rpplAccent)
    }
}
