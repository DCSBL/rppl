import Observation
import RpplCore
import SwiftUI

/// Single place the Parks UI reads and writes parks (bundled + user files).
@Observable
@MainActor
final class ParkStore {
    static let shared = ParkStore()

    private(set) var entries: [ParkEntry] = []

    private var root: URL { AppConstants.localPhoneParksRoot }

    func reload() {
        entries = ParkCatalog.loadWithOrigin(userRoot: root)
    }

    func entry(id: String) -> ParkEntry? {
        entries.first { $0.id == id }
    }

    func save(_ park: Park) throws {
        let existing = entry(id: park.id)
        let base: Park? = switch existing?.origin {
        case .bundled: existing?.park
        case .edited: existing?.bundledPark
        default: nil
        }
        try ParkCatalog.save(park, to: root, bundledBase: base)
        reload()
    }

    /// Deletes a custom park or drops an override so the bundled park shows again.
    func removeUserVersion(id: String) {
        do { try ParkCatalog.deleteUserPark(id: id, userRoot: root) } catch {
            WakeLog.error(.store, "park delete \(id): \(error.localizedDescription)")
        }
        reload()
    }

    func keepMine(_ entry: ParkEntry) {
        do { try ParkCatalog.keepMine(entry, userRoot: root) } catch {
            WakeLog.error(.store, "park keep \(entry.id): \(error.localizedDescription)")
        }
        reload()
    }

    func newParkID(for name: String) -> String {
        ParkCatalog.slug(from: name, existing: Set(entries.map(\.id)))
    }
}
