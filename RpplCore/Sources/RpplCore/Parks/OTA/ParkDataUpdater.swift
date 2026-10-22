import Foundation

/// Fetches a path relative to the distribution branch (`manifest.json`, `<id>.yaml`).
public protocol ParkDataFetching: Sendable {
    func fetch(_ path: String, maxBytes: Int) async throws -> Data
}

public enum ParkDataUpdateOutcome: Equatable, Sendable {
    case updated(dataVersion: Int)
    case upToDate(dataVersion: Int)
    /// The manifest's kill switch is on: bundled parks are shown.
    case disabled
    /// The data needs a newer app than this one.
    case appUpdateRequired
}

public struct ParkDataUpdater: Sendable {
    public let store: ParkDataStore
    public let appSchema: Int

    public init(store: ParkDataStore, appSchema: Int = Park.currentVersion) {
        self.store = store
        self.appSchema = appSchema
    }

    /// Checks the manifest and installs new data when it differs from what is installed. Only
    /// files whose hash changed are downloaded. Throws without touching installed data on any failure.
    public func update(using fetcher: ParkDataFetching) async throws -> ParkDataUpdateOutcome {
        let manifestData = try await fetcher.fetch("manifest.json", maxBytes: ParkDataManifest.maxManifestBytes)
        let manifest = try ParkDataManifest.decode(manifestData)

        guard manifest.enabled else {
            try store.setEnabled(false)
            return .disabled
        }
        do {
            try manifest.validateHeader(appSchema: appSchema)
        } catch ParkDataError.appUpdateRequired {
            return .appUpdateRequired
        }

        if let pointer = store.pointer(), pointer.dataVersion == manifest.dataVersion, store.installedDirectory() != nil {
            try store.setEnabled(true)
            return .upToDate(dataVersion: manifest.dataVersion)
        }

        var files: [String: Data] = [:]
        for entry in manifest.parks {
            if let local = store.installedFile(entry.file), ParkDataHash.sha256Hex(local) == entry.sha256.lowercased() {
                files[entry.file] = local
            } else {
                files[entry.file] = try await fetcher.fetch(entry.file, maxBytes: ParkDataManifest.maxParkFileBytes)
            }
        }
        try store.install(manifest: manifest, files: files)
        return .updated(dataVersion: manifest.dataVersion)
    }
}
