import Foundation
import Observation
import RpplCore

/// Debug: the tower verdicts collected on this phone and the request that says which parks to
/// review. Both live in Documents/tower-review/ so a session can stop and resume; the labels file
/// is shared as `tower-labels.json` and read by the cable-tracer's training-set export.
@Observable
@MainActor
final class TowerReviewStore {
    static let shared = TowerReviewStore()

    private(set) var labels = TowerLabelStore()
    private(set) var request: TowerReviewRequest?
    private(set) var lastError: String?

    /// A park to review: from the request when there is one, else every park without a traced cable.
    struct Row: Identifiable {
        var id: String
        var name: String
        var reason: String?
        /// nil when the request names a park this phone does not have.
        var park: Park?
    }

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tower-review", isDirectory: true)
    }
    /// Where builds before the rename (2026-11-03) kept the labels; read once and saved under the new name.
    private var legacyLabelsFile: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mast-review", isDirectory: true)
            .appendingPathComponent(TowerLabelStore.legacyFileName)
    }
    private var labelsFile: URL { directory.appendingPathComponent(TowerLabelStore.fileName) }
    private var requestFile: URL { directory.appendingPathComponent("tower-review-request.json") }

    private init() {
        load()
    }

    func load() {
        do {
            if !FileManager.default.fileExists(atPath: labelsFile.path), FileManager.default.fileExists(atPath: legacyLabelsFile.path) {
                labels = try TowerLabelStore.load(from: legacyLabelsFile)
                saveLabels()
            } else {
                labels = try TowerLabelStore.load(from: labelsFile)
            }
            if FileManager.default.fileExists(atPath: requestFile.path) {
                request = try TowerReviewRequest.decode(Data(contentsOf: requestFile))
            }
        } catch {
            lastError = error.localizedDescription
            WakeLog.error(.store, "tower review load: \(error.localizedDescription)")
        }
    }

    func rows(entries: [ParkEntry]) -> [Row] {
        let parks = Dictionary(entries.map { ($0.park.id, $0.park) }, uniquingKeysWith: { first, _ in first })
        if let request {
            return request.parks.map { item in
                Row(id: item.id, name: parks[item.id]?.name ?? item.name ?? item.id, reason: item.reason, park: parks[item.id])
            }
        }
        return entries
            .map(\.park)
            .filter { !($0.cables ?? []).contains { ($0.points ?? []).count >= 2 } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { Row(id: $0.id, name: $0.name, reason: nil, park: $0) }
    }

    func add(_ label: TowerLabel, to parkID: String) {
        labels.add(label, to: parkID)
        saveLabels()
    }

    func remove(_ id: UUID, from parkID: String) {
        labels.remove(id, from: parkID)
        saveLabels()
    }

    private func saveLabels() {
        do {
            try labels.save(to: labelsFile)
        } catch {
            lastError = error.localizedDescription
            WakeLog.error(.store, "tower review save: \(error.localizedDescription)")
        }
    }

    /// Reads a request picked in the file importer (a security-scoped URL).
    func importRequest(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let imported = try TowerReviewRequest.decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try imported.encoded().write(to: requestFile, options: .atomic)
        request = imported
    }

    func clearRequest() {
        request = nil
        try? FileManager.default.removeItem(at: requestFile)
    }

    /// Presents the share sheet with the labels file (AirDrop, Files, Mail, …).
    func shareResults() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(TowerLabelStore.fileName)
            try labels.encoded().write(to: url, options: .atomic)
            ActivitySharePresenter.present(items: [url])
        } catch {
            lastError = error.localizedDescription
            WakeLog.error(.store, "tower review share: \(error.localizedDescription)")
        }
    }
}
