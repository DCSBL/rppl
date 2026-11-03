import MapKit
import RpplCore
import SwiftUI

/// Debug: satellite map of one park. "Find towers" runs the tower detector around the map centre;
/// the guesses come up one by one (most confident first) under the crosshair, and each gets a
/// verdict. Pan the crosshair onto the real tower before "Tower" to correct the position; use
/// "Add tower here" for towers the detector missed.
struct MastReviewMapView: View {
    let park: Park

    private var store: MastReviewStore { .shared }

    @State private var position: MapCameraPosition
    @State private var viewCenter: CLLocationCoordinate2D
    @State private var session: MastReviewSession?
    @State private var detecting = false
    @State private var detectionNote: String?
    @State private var removing: MastLabel?

    /// Span of the map when a candidate is shown: close enough to see a single tower.
    private static let candidateSpanM = 90.0

    init(park: Park) {
        self.park = park
        let start = CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
        _viewCenter = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(center: start, latitudinalMeters: 600, longitudinalMeters: 600)))
    }

    private var centerCoordinate: ParkCoordinate {
        ParkCoordinate(lat: viewCenter.latitude, lon: viewCenter.longitude)
    }

    private var labels: [MastLabel] { store.labels.labels(for: park.id) }

    var body: some View {
        Map(position: $position) {
            ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                if let line = cable.points?.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }), line.count >= 2 {
                    MapPolyline(coordinates: cable.direction?.isLoop == true ? line + [line[0]] : line)
                        .stroke(Color.rpplMuted.opacity(0.8), lineWidth: 2)
                }
            }
            ForEach(labels) { label in
                Annotation("", coordinate: mapCoordinate(label.coordinate), anchor: .center) {
                    Button {
                        removing = label
                    } label: {
                        ring(color: color(of: label.verdict), size: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(accessibilityName(of: label.verdict)))
                }
            }
            if let session {
                ForEach(session.candidates) { candidate in
                    if candidate.id != session.current?.id {
                        Annotation("", coordinate: mapCoordinate(candidate.coordinate), anchor: .center) {
                            Circle()
                                .fill(Color.purple.opacity(0.4 + 0.6 * candidate.probability))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        }
                    }
                }
                if let current = session.current {
                    Annotation("", coordinate: mapCoordinate(current.coordinate), anchor: .center) {
                        ring(color: .orange, size: 34)
                    }
                }
            }
        }
        .mapStyle(.hybrid(elevation: .flat))
        .onMapCameraChange(frequency: .continuous) { context in
            viewCenter = context.camera.centerCoordinate
        }
        .overlay { MapCrosshair() }
        .overlay(alignment: .top) {
            if detecting {
                ProgressView("Looking for towers…")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle(park.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    findMasts()
                } label: {
                    Label("Find towers", systemImage: "scope")
                }
                .disabled(detecting)
            }
        }
        .alert("Remove this label?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { label in
            Button("Remove", role: .destructive) { store.remove(label.id, from: park.id) }
            Button("Cancel", role: .cancel) {}
        } message: { label in
            Text(accessibilityName(of: label.verdict))
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(summary)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let detectionNote {
                    Text(detectionNote).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let session, let current = session.current, let index = session.position {
                HStack {
                    Text("Guess \(index) of \(session.remaining) · \(Int((current.probability * 100).rounded())) %")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Show") { fly(to: current.coordinate) }
                    Button("Skip") {
                        self.session?.skip()
                        if let next = self.session?.current { fly(to: next.coordinate) }
                    }
                }
                HStack(spacing: 8) {
                    verdictButton("Tower", color: .green) { judge(.mast) }
                    verdictButton("No tower", color: .red) { judge(.notMast) }
                    verdictButton("Unsure", color: .gray) { judge(.unsure) }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        findMasts()
                    } label: {
                        Label(session == nil ? "Find towers around the centre" : "Look again around the centre", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(detecting)
                }
            }
            Button {
                store.add(MastReviewSession.manualMast(at: centerCoordinate), to: park.id)
            } label: {
                Label("Add tower here", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.rpplAccent)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func verdictButton(_ title: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

    private var summary: String {
        let masts = store.labels.count(.mast, in: park.id)
        let none = store.labels.count(.notMast, in: park.id)
        let unsure = store.labels.count(.unsure, in: park.id)
        return "\(masts) towers · \(none) no tower · \(unsure) unsure"
    }

    // MARK: Actions

    private func findMasts() {
        detecting = true
        detectionNote = nil
        let center = centerCoordinate
        let parkID = park.id
        let known = store.labels
        Task {
            do {
                let image = try await CableDetectionRunner.snapshot(around: center)
                let result = await Task.detached(priority: .userInitiated) {
                    var options = CableDetector.Options()
                    options.minimumMastProbability = MastReviewSession.minimumProbability
                    options.fitLoops = false
                    return CableDetector.detect(in: image, options: options)
                }.value
                let found = MastReviewSession(parkID: parkID, detected: result.masts, image: image, labels: known)
                session = found
                detectionNote = found.remaining == 0
                    ? (result.masts.isEmpty ? String(localized: "No towers found") : String(localized: "All guesses here are judged"))
                    : nil
                if let first = found.current { fly(to: first.coordinate) }
            } catch {
                detectionNote = error.localizedDescription
            }
            detecting = false
        }
    }

    private func judge(_ verdict: MastLabel.Verdict) {
        guard let label = session?.judge(verdict, crosshair: centerCoordinate) else { return }
        store.add(label, to: park.id)
        if let next = session?.current { fly(to: next.coordinate) }
    }

    private func fly(to coordinate: ParkCoordinate) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: mapCoordinate(coordinate), latitudinalMeters: Self.candidateSpanM, longitudinalMeters: Self.candidateSpanM))
        }
    }

    // MARK: Helpers

    private func mapCoordinate(_ coordinate: ParkCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
    }

    private func ring(color: Color, size: CGFloat) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: 3)
            .frame(width: size, height: size)
            .background(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1).padding(-1))
            .shadow(color: .black.opacity(0.5), radius: 2)
    }

    private func color(of verdict: MastLabel.Verdict) -> Color {
        switch verdict {
        case .mast: .green
        case .notMast: .red
        case .unsure: .gray
        }
    }

    private func accessibilityName(of verdict: MastLabel.Verdict) -> String {
        switch verdict {
        case .mast: String(localized: "Tower")
        case .notMast: String(localized: "No tower")
        case .unsure: String(localized: "Unsure")
        }
    }
}
