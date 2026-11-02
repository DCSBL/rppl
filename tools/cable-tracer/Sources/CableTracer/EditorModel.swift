import AppKit
import CableTracerCore
import Foundation
import MapKit
import Observation
import RpplCore

/// Which cable kind to add; the reviewer picks, the shape prior fills in a first guess.
enum TemplateKind: String, CaseIterable, Identifiable {
    case loop = "Full size"
    case straight = "2.0"
    var id: String { rawValue }
}

@MainActor
@Observable
final class EditorModel {
    private(set) var workspace: ParkWorkspace?
    private(set) var parks: [Park] = []
    private(set) var prior: CablePrior = .bundled
    var reference: ReferencePoints = ReferencePoints()

    var searchText = ""
    var onlyUntraced = false
    var selectedParkID: String? {
        didSet { if oldValue != selectedParkID { loadDraft() } }
    }
    /// Editable copy of the selected park; `parks` keeps what is on disk.
    private(set) var draft: Park?
    var selectedCableIndex: Int?
    var isAddingPoints = false
    /// Bumped on every geometry change so the map rebuilds its overlays once per change.
    private(set) var revision = 0
    /// Bumped when the map should fly to the selected park.
    private(set) var focusRequest = 0
    var statusMessage = ""

    var isDirty: Bool {
        guard let draft, let original = parks.first(where: { $0.id == draft.id }) else { return false }
        return draft != original
    }

    var findings: [CableLintFinding] { draft.map { CableLint.check($0) } ?? [] }

    var filteredParks: [Park] {
        parks.filter { park in
            if onlyUntraced, park.cables?.contains(where: { ($0.points?.count ?? 0) >= 2 }) == true { return false }
            guard !searchText.isEmpty else { return true }
            return park.name.localizedCaseInsensitiveContains(searchText) || park.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Loading

    func openDefaultDirectory() {
        guard workspace == nil, let url = ParkWorkspace.locateBundledParks() else { return }
        open(directory: url)
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the folder with park YAML files"
        if panel.runModal() == .OK, let url = panel.url { open(directory: url) }
    }

    func open(directory: URL) {
        let workspace = ParkWorkspace(directory: directory)
        self.workspace = workspace
        parks = workspace.load()
        prior = CablePrior.learn(from: parks)
        statusMessage = "\(parks.count) parks from \(directory.path)"
        if selectedParkID == nil { selectedParkID = parks.first?.id } else { loadDraft() }
    }

    func reload() {
        guard let workspace else { return }
        parks = workspace.load()
        prior = CablePrior.learn(from: parks)
        loadDraft()
    }

    private func loadDraft() {
        draft = parks.first { $0.id == selectedParkID }
        selectedCableIndex = (draft?.cables?.isEmpty == false) ? 0 : nil
        isAddingPoints = false
        revision += 1
        focusRequest += 1
    }

    /// Map region that shows the park and everything traced there.
    var focusRegion: MKCoordinateRegion? {
        guard let draft else { return nil }
        var coordinates = [draft.location]
        for cable in draft.cables ?? [] { coordinates += (cable.points ?? []).map(\.coordinate) }
        for point in reference.points(for: draft.id) { coordinates.append(point.coordinate) }
        let lats = coordinates.map(\.lat), lons = coordinates.map(\.lon)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let minSpan = 0.012  // ~1.3 km: enough for a full-size loop around the park point
        let span = MKCoordinateSpan(
            latitudeDelta: max(minSpan, (lats.max()! - lats.min()!) * 1.6),
            longitudeDelta: max(minSpan / cos(center.latitude * .pi / 180), (lons.max()! - lons.min()!) * 1.6)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    func focus() { focusRequest += 1 }

    // MARK: Editing

    private func mutate(_ change: (inout Park) -> Void) {
        guard var park = draft else { return }
        change(&park)
        draft = park
        revision += 1
    }

    func addCable(_ kind: TemplateKind) {
        guard let draft else { return }
        let cable: ParkCable
        switch kind {
        case .loop: cable = CableTemplate.loop(at: draft.location, prior: prior.loop)
        case .straight: cable = CableTemplate.straight(at: draft.location, prior: prior.straight)
        }
        mutate { $0.cables = ($0.cables ?? []) + [cable] }
        selectedCableIndex = (self.draft?.cables?.count ?? 1) - 1
        statusMessage = "Added a \(kind.rawValue) template of the median shape; drag its points into place"
    }

    /// Replaces an untraced cable's points with a template of the kind its direction suggests.
    func fillTemplate(cableIndex: Int) {
        guard let draft, let cable = draft.cables?[safe: cableIndex] else { return }
        let kind: TemplateKind = cable.direction == .twoPointZero ? .straight : .loop
        let template = kind == .loop
            ? CableTemplate.loop(at: draft.location, prior: prior.loop, direction: cable.direction?.isLoop == true ? cable.direction! : .counterClockwise)
            : CableTemplate.straight(at: draft.location, prior: prior.straight)
        mutate {
            $0.cables?[cableIndex].points = template.points
            if $0.cables?[cableIndex].direction == nil { $0.cables?[cableIndex].direction = template.direction }
        }
    }

    func rotateSelectedCable(by degrees: Double) {
        guard let draft, let index = selectedCableIndex, let cable = draft.cables?[safe: index] else { return }
        let rotated = CableTemplate.rotated(cable, by: degrees, parkLocation: draft.location)
        mutate { $0.cables?[index] = rotated }
    }

    func removeCable(at index: Int) {
        mutate { $0.cables?.remove(at: index) }
        if draft?.cables?.isEmpty == true { mutate { $0.cables = nil } }
        selectedCableIndex = draft?.cables?.isEmpty == false ? min(index, (draft?.cables?.count ?? 1) - 1) : nil
    }

    func updateCable(at index: Int, _ change: (inout ParkCable) -> Void) {
        mutate { if $0.cables?.indices.contains(index) == true { change(&$0.cables![index]) } }
    }

    func appendPoint(_ coordinate: CLLocationCoordinate2D) {
        guard let index = selectedCableIndex else {
            statusMessage = "Select or add a cable first"
            return
        }
        updateCable(at: index) { cable in
            var points = cable.points ?? []
            points.append(ParkCablePoint(lat: coordinate.latitude, lon: coordinate.longitude, start: points.isEmpty ? true : nil))
            cable.points = points
        }
    }

    func movePoint(cable cableIndex: Int, point pointIndex: Int, to coordinate: CLLocationCoordinate2D) {
        updateCable(at: cableIndex) { cable in
            guard cable.points?.indices.contains(pointIndex) == true else { return }
            cable.points?[pointIndex].lat = coordinate.latitude
            cable.points?[pointIndex].lon = coordinate.longitude
        }
    }

    func removePoint(cable cableIndex: Int, point pointIndex: Int) {
        updateCable(at: cableIndex) { cable in
            guard cable.points?.indices.contains(pointIndex) == true else { return }
            cable.points?.remove(at: pointIndex)
            if cable.points?.isEmpty == true { cable.points = nil }
        }
    }

    func toggleStart(cable cableIndex: Int, point pointIndex: Int) {
        updateCable(at: cableIndex) { cable in
            guard cable.points?.indices.contains(pointIndex) == true else { return }
            cable.points?[pointIndex].start = cable.points?[pointIndex].start == true ? nil : true
        }
    }

    func reversePoints(cable cableIndex: Int) {
        updateCable(at: cableIndex) { $0.points?.reverse() }
    }

    func discardChanges() { loadDraft() }

    // MARK: Saving

    func save() {
        guard let workspace, let draft, isDirty else { return }
        let description = (parks.first { $0.id == draft.id }?.cables?.contains { ($0.points?.count ?? 0) >= 2 } == true)
            ? "adjust cable route on the map (cable-tracer)"
            : "trace cable route on the map (cable-tracer)"
        do {
            try workspace.save(draft, historyDescription: description)
            let id = draft.id
            parks = workspace.load()
            prior = CablePrior.learn(from: parks)
            self.draft = parks.first { $0.id == id }
            revision += 1
            statusMessage = "Saved \(workspace.fileURL(for: id).lastPathComponent)"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: Training set

    var isExporting = false

    /// Writes `training-set.json` plus a satellite snapshot and a cable mask per traced park.
    func exportTrainingSet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Folder for the training set (JSON + satellite snapshots)"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let parks = self.parks
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                var rows = TrainingSet.rows(parks: parks, tracedOnly: false)
                for index in rows.indices {
                    statusMessage = "Snapshot \(index + 1)/\(rows.count): \(rows[index].name)"
                    rows[index].snapshot = try await SnapshotExporter.export(row: rows[index], into: directory)
                }
                try TrainingSet.encode(rows).write(to: directory.appendingPathComponent("training-set.json"))
                statusMessage = "Exported \(rows.count) parks to \(directory.path)"
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
