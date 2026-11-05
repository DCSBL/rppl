import MapKit
import RpplCore
import SwiftUI

/// Debug: satellite map of one park. "Find towers" runs the tower detector around the map centre;
/// the guesses come up one by one (the most confident first, then always the nearest one) under the
/// frame's ring, and each gets a verdict. The frame stays put: pan, rotate and zoom the map until the
/// wheel sits in the ring and the tower's arm lies along the frame with its foot at the left end, then
/// tap "Tower". Rotation and zoom are kept between guesses, so the next tower mostly needs a pan.
/// "Add tower here" and "Not visible here" cover towers the detector missed.
struct TowerReviewMapView: View {
    let park: Park

    private var store: TowerReviewStore { .shared }

    @State private var position: MapCameraPosition
    @State private var viewCenter: CLLocationCoordinate2D
    @State private var session: TowerReviewSession?
    @State private var detecting = false
    @State private var detectionNote: String?
    @State private var removing: TowerLabel?
    /// Where the frame's left end (the tower's foot) is on the map.
    @State private var foot: ParkCoordinate?
    @State private var camera: MapCamera?
    /// Close-up check per guess (by candidate id), and the close-up it looked at (kept at 256 px).
    @State private var closeupScores: [Int: Double] = [:]
    @State private var closeups: [Int: DetectionImage] = [:]
    @State private var checking: Task<Void, Never>?
    @AppStorage(AppSettingsKey.debugTowerCloseupCheck) private var closeupCheckEnabled = true

    /// Camera distance when a park opens zoomed out: close enough to see a single tower.
    private static let candidateDistanceM = 160.0
    /// Frame length on screen, from the ring to the foot end.
    static let frameLengthPt: CGFloat = 150

    init(park: Park) {
        self.park = park
        let start = CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
        _viewCenter = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(center: start, latitudinalMeters: 600, longitudinalMeters: 600)))
    }

    private var centerCoordinate: ParkCoordinate {
        ParkCoordinate(lat: viewCenter.latitude, lon: viewCenter.longitude)
    }

    private var labels: [TowerLabel] { store.labels.labels(for: park.id) }

    /// The arm along the frame right now: from the ring to the frame's left end.
    private var arm: TowerLabel.Arm? { foot.flatMap { TowerLabel.Arm(wheel: centerCoordinate, foot: $0) } }

    var body: some View {
        MapReader { proxy in
            map(proxy)
        }
    }

    private func map(_ proxy: MapProxy) -> some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
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
            // Pinned to the map centre as an annotation, so the ring is exactly where a label is saved
            // (an overlay drifted from the centre by the navigation bar's height). Annotations stay
            // upright when the map rotates.
            Annotation("", coordinate: viewCenter, anchor: .center) {
                TowerFrame(armLengthM: arm?.lengthM)
                    .allowsHitTesting(false)
            }
        }
        .mapStyle(.hybrid(elevation: .flat))
        .onMapCameraChange(frequency: .continuous) { context in
            viewCenter = context.camera.centerCoordinate
            camera = context.camera
            // The foot is one frame length left of the centre on screen; both conversions use the
            // map's own space, so the arm is right wherever the map sits in the view.
            foot = proxy.convert(context.camera.centerCoordinate, to: .local)
                .flatMap { proxy.convert(CGPoint(x: $0.x - Self.frameLengthPt, y: $0.y), from: .local) }
                .map { ParkCoordinate(lat: $0.latitude, lon: $0.longitude) }
        }
        .overlay(alignment: .top) {
            if detecting {
                ProgressView("Looking for towers…")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .onDisappear { checking?.cancel() }
        .navigationTitle(park.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    findTowers()
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Guess \(index) of \(session.remaining) · \(Int((current.probability * 100).rounded())) %")
                            .font(.subheadline.weight(.semibold))
                        if closeupCheckEnabled {
                            closeupLine(for: current.id)
                        }
                    }
                    Spacer()
                    Button("Show") { fly(to: current.coordinate) }
                    Button("Skip") {
                        self.session?.skip()
                        if let next = self.session?.current { fly(to: next.coordinate) }
                    }
                }
                verdictButton("Tower fits the frame", color: .green) { judge(.tower) }
                HStack(spacing: 8) {
                    verdictButton("No tower", color: .red) { judge(.notTower) }
                    verdictButton("Not visible", color: .cyan) { judge(.notVisible) }
                    verdictButton("Unsure", color: .gray) { judge(.unsure) }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        findTowers()
                    } label: {
                        Label(session == nil ? "Find towers around the centre" : "Look again around the centre", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(detecting)
                }
            }
            HStack(spacing: 8) {
                Button {
                    store.add(TowerReviewSession.manualTower(at: centerCoordinate, arm: arm), to: park.id)
                } label: {
                    Label("Add tower here", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    store.add(TowerReviewSession.manualNotVisible(at: centerCoordinate), to: park.id)
                } label: {
                    Label("Not visible here", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
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
        let towers = store.labels.count(.tower, in: park.id)
        let none = store.labels.count(.notTower, in: park.id)
        let hidden = store.labels.count(.notVisible, in: park.id)
        let unsure = store.labels.count(.unsure, in: park.id)
        return "\(towers) towers · \(none) no tower · \(hidden) not visible · \(unsure) unsure"
    }

    // MARK: Actions

    private func findTowers() {
        detecting = true
        detectionNote = nil
        let center = centerCoordinate
        let parkID = park.id
        let known = store.labels
        Task {
            do {
                let image = try await CableDetectionRunner.snapshot(around: center)
                store.saveSnapshot(image, parkID: parkID)
                let result = await Task.detached(priority: .userInitiated) {
                    var options = CableDetector.Options()
                    options.minimumTowerProbability = TowerReviewSession.minimumProbability
                    options.fitLoops = false
                    return CableDetector.detect(in: image, options: options)
                }.value
                let found = TowerReviewSession(parkID: parkID, detected: result.towers, image: image, labels: known)
                session = found
                startCloseupChecks(for: found)
                detectionNote = found.remaining == 0
                    ? (result.towers.isEmpty ? String(localized: "No towers found") : String(localized: "All guesses here are judged"))
                    : nil
                if let first = found.current { fly(to: first.coordinate) }
            } catch {
                detectionNote = error.localizedDescription
            }
            detecting = false
        }
    }

    private func judge(_ verdict: TowerLabel.Verdict) {
        let id = session?.current?.id
        let score = id.flatMap { closeupScores[$0] }
        guard let label = session?.judge(verdict, crosshair: centerCoordinate, arm: arm, closeupScore: score) else { return }
        store.add(label, to: park.id)
        // The close-up is centred on the guess: it only serves as the label's own when the label stayed there.
        if let id, let closeup = closeups[id], label.detected == nil {
            store.saveCloseup(closeup, for: label, parkID: park.id)
        }
        if let next = session?.current { fly(to: next.coordinate) }
    }

    /// Puts the guess under the ring, keeping the reviewer's rotation and zoom once they are close in.
    private func fly(to coordinate: ParkCoordinate) {
        // Still zoomed out from opening the park: come down to tower level.
        let distance = camera.map { $0.distance > Self.candidateDistanceM * 2 ? Self.candidateDistanceM : $0.distance } ?? Self.candidateDistanceM
        withAnimation {
            position = .camera(MapCamera(centerCoordinate: mapCoordinate(coordinate), distance: distance, heading: camera?.heading ?? 0, pitch: 0))
        }
    }

    // MARK: Close-up check

    @ViewBuilder
    private func closeupLine(for id: Int) -> some View {
        if let score = closeupScores[id] {
            Text("Close-up check \(Int((score * 100).rounded())) % · \(score >= 0.5 ? "tower" : "no tower")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(score >= 0.5 ? Color.green : Color.red)
        } else if TowerCloseupCheck.bundled == nil {
            Text("Close-up check not bundled").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Close-up check…").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Fetches the 40 m close-up of every guess, in review order, and scores it; one at a time.
    private func startCloseupChecks(for found: TowerReviewSession) {
        checking?.cancel()
        closeupScores = [:]
        closeups = [:]
        guard closeupCheckEnabled, let check = TowerCloseupCheck.bundled else { return }
        let candidates = found.candidates
        let keptPixels = TowerReviewStore.closeupKeptPixels
        checking = Task {
            for candidate in candidates {
                if Task.isCancelled { return }
                do {
                    let closeup = try await CableDetectionRunner.closeup(around: candidate.coordinate)
                    let (score, kept) = await Task.detached(priority: .userInitiated) {
                        let kept = closeup.downsampled(by: closeup.width / keptPixels)
                        return (check.score(kept), kept)
                    }.value
                    if Task.isCancelled { return }
                    closeupScores[candidate.id] = score
                    closeups[candidate.id] = kept
                } catch {
                    WakeLog.error(.store, "tower close-up check: \(error.localizedDescription)")
                }
            }
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

    private func color(of verdict: TowerLabel.Verdict) -> Color {
        switch verdict {
        case .tower: .green
        case .notTower: .red
        case .notVisible: .cyan
        case .unsure: .gray
        }
    }

    private func accessibilityName(of verdict: TowerLabel.Verdict) -> String {
        switch verdict {
        case .tower: String(localized: "Tower")
        case .notTower: String(localized: "No tower")
        case .notVisible: String(localized: "Not visible")
        case .unsure: String(localized: "Unsure")
        }
    }
}

/// The fixed review frame: the ring for the wheel at the centre (where the frame is positioned) and
/// the frame running left to the tower's foot, with the arm length it spans on the map right now.
private struct TowerFrame: View {
    let armLengthM: Double?

    private let length = TowerReviewMapView.frameLengthPt
    private let margin: CGFloat = 14
    private let height: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.yellow, lineWidth: 2)
                .frame(width: length + margin, height: height)
                .offset(x: (margin - length) / 2)
            Circle()
                .strokeBorder(Color.yellow, lineWidth: 2)
                .frame(width: 14, height: 14)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 8, height: 2)
                .offset(x: -length + 4)
            if let armLengthM {
                Text("\(Int(armLengthM.rounded())) m")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
                    .offset(x: -length / 2, y: height / 2 + 10)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 1.5)
        .frame(width: 2 * length + 2 * margin, height: height + 40)
        .accessibilityHidden(true)
    }
}
