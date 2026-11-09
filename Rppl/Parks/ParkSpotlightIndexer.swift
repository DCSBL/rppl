import CoreSpotlight
import Foundation
import RpplCore
import UniformTypeIdentifiers

/// Puts the parks in the system search (Spotlight) while the "Parks in Spotlight" debug toggle is on.
///
/// The parks live in the app's own named index, rewritten in one batch whose client state is a
/// fingerprint of what was indexed (`ParkSpotlight.fingerprint`). A launch with the same parks reads that
/// state and stops; an index the system dropped has no state, so it is filled again. A tapped result comes
/// back as a `CSSearchableItemActionType` activity, which `ContentView` turns into the park link.
///
/// Core Spotlight wants one change to a custom index at a time, so every run waits for the one before it.
@MainActor
final class ParkSpotlightIndexer {
    static let shared = ParkSpotlightIndexer()

    /// Client state of an index that holds no finished set of parks: after a removal or a failed run.
    /// A fingerprint is a hex string, so this never matches one.
    private static let emptyState = "none"

    private lazy var searchIndex = CSSearchableIndex(name: ParkSpotlight.domain)
    private var lastRun: Task<Void, Never>?
    /// The fingerprint this process last saw in the index, so a second look is skipped while nothing changed.
    private var knownFingerprint: String?

    /// Indexes `parks` when they differ from what the index holds.
    func sync(parks: [Park]) {
        enqueue { await self.refresh(parks: parks) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = lastRun
        lastRun = Task {
            await previous?.value
            await work()
        }
    }

    private func refresh(parks: [Park]) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entries = ParkSpotlight.entries(for: parks)
        let fingerprint = ParkSpotlight.fingerprint(of: entries)
        guard fingerprint != knownFingerprint else { return }
        if await storedState() == fingerprint {
            knownFingerprint = fingerprint
            return
        }
        await rebuild(entries, fingerprint: fingerprint)
    }

    /// What the last finished batch stored: a fingerprint, `emptyState`, or nil for an index without any.
    private func storedState() async -> String? {
        let index = searchIndex
        return await withCheckedContinuation { continuation in
            index.fetchLastClientState { state, _ in
                continuation.resume(returning: state.flatMap { String(data: $0, encoding: .utf8) })
            }
        }
    }

    private func rebuild(_ entries: [ParkSpotlightEntry], fingerprint: String) async {
        let index = searchIndex
        let items = entries.map(Self.searchableItem(for:))
        var finished = false
        index.beginBatch()
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [ParkSpotlight.domain])
            try await index.indexSearchableItems(items)
            finished = true
        } catch {
            WakeLog.error(.store, "park spotlight index: \(error.localizedDescription)")
        }
        let closed = await endBatch(of: index, state: finished ? fingerprint : Self.emptyState)
        knownFingerprint = finished && closed ? fingerprint : nil
    }

    /// Always closes the batch, so a failed run never leaves one open; its state tells the next launch to try again.
    /// False when the state could not be stored.
    private func endBatch(of index: CSSearchableIndex, state: String) async -> Bool {
        do {
            try await index.endBatch(withClientState: Data(state.utf8))
            return true
        } catch {
            WakeLog.error(.store, "park spotlight batch: \(error.localizedDescription)")
            return false
        }
    }

    private static func searchableItem(for entry: ParkSpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.contentDescription = entry.subtitle
        attributes.keywords = entry.keywords
        attributes.latitude = NSNumber(value: entry.latitude)
        attributes.longitude = NSNumber(value: entry.longitude)
        // With a position, Spotlight offers directions to the park.
        attributes.supportsNavigation = NSNumber(value: true)
        let item = CSSearchableItem(
            uniqueIdentifier: entry.identifier,
            domainIdentifier: ParkSpotlight.domain,
            attributeSet: attributes
        )
        // Without an expiration date the system lets the item lapse after a while.
        item.expirationDate = .distantFuture
        return item
    }
}
