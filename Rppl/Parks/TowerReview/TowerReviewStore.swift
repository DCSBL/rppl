import Foundation
import Observation
import RpplCore
import UIKit

/// Debug: the tower verdicts collected on this phone, the request that says which parks to review,
/// and the satellite close-ups the reviews ran on. All live in Documents/tower-review/ so a session
/// can stop and resume. "Share results" hands over one zip with `tower-labels.json` and
/// `snapshots/` (a JPEG plus a `TowerReviewSnapshot` JSON per look), from which
/// `tools/cable-tracer/detect/phone_set.py` builds the training set without a Mac.
@Observable
@MainActor
final class TowerReviewStore {
    static let shared = TowerReviewStore()

    private(set) var labels = TowerLabelStore()
    private(set) var request: TowerReviewRequest?
    private(set) var lastError: String?
    /// Saved close-ups (one per "Find towers").
    private(set) var snapshotCount = 0

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
    private var snapshotsDirectory: URL { directory.appendingPathComponent("snapshots", isDirectory: true) }

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
            countSnapshots()
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

    // MARK: Snapshots

    /// Keeps the close-up a "Find towers" ran on, encoded off the main actor.
    func saveSnapshot(_ image: DetectionImage, parkID: String) {
        let snapshot = TowerReviewSnapshot(parkID: parkID, image: image)
        let folder = snapshotsDirectory
        Task.detached(priority: .utility) {
            do {
                guard let jpeg = Self.jpegData(image) else { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try jpeg.write(to: folder.appendingPathComponent(snapshot.fileStem + ".jpg"), options: .atomic)
                try snapshot.encoded().write(to: folder.appendingPathComponent(snapshot.fileStem + ".json"), options: .atomic)
                await MainActor.run { TowerReviewStore.shared.countSnapshots() }
            } catch {
                WakeLog.error(.store, "tower review snapshot: \(error.localizedDescription)")
            }
        }
    }

    private func countSnapshots() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: snapshotsDirectory.path)) ?? []
        snapshotCount = files.filter { $0.hasSuffix(".jpg") }.count
    }

    /// JPEG at high quality: about 1 MB for a 2048 px close-up, against 6-8 MB as PNG.
    nonisolated static func jpegData(_ image: DetectionImage) -> Data? {
        let pixels = image.width * image.height
        var rgbx = [UInt8](repeating: 255, count: pixels * 4)
        for index in 0..<pixels {
            rgbx[index * 4] = image.rgb[index * 3]
            rgbx[index * 4 + 1] = image.rgb[index * 3 + 1]
            rgbx[index * 4 + 2] = image.rgb[index * 3 + 2]
        }
        guard let provider = CGDataProvider(data: Data(rgbx) as CFData),
              let cgImage = CGImage(
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: image.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92)
    }

    // MARK: Sharing

    /// Presents the share sheet with one zip (AirDrop, Files, Mail, …): the labels file and every
    /// saved close-up.
    func shareResults() {
        do {
            ActivitySharePresenter.present(items: [try resultsZip()])
        } catch {
            lastError = error.localizedDescription
            WakeLog.error(.store, "tower review share: \(error.localizedDescription)")
        }
    }

    private func resultsZip() throws -> URL {
        let fileManager = FileManager.default
        let name = "tower-review-\(TowerLabelStore.today())"
        let staging = fileManager.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try labels.encoded().write(to: staging.appendingPathComponent(TowerLabelStore.fileName), options: .atomic)
        if fileManager.fileExists(atPath: snapshotsDirectory.path) {
            try fileManager.copyItem(at: snapshotsDirectory, to: staging.appendingPathComponent("snapshots", isDirectory: true))
        }
        // Reading a folder with .forUploading hands back a zip of it.
        let zip = fileManager.temporaryDirectory.appendingPathComponent(name + ".zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try? fileManager.removeItem(at: zip)
                try fileManager.copyItem(at: zipped, to: zip)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return zip
    }
}
