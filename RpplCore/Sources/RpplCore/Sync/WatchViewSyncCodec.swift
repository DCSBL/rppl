import Foundation

public enum WatchViewSyncMessageType: String, Sendable {
    case viewUpdate
    case viewDelete
    case syncRequest
    case syncReply
}

/// Phone → Watch distilled session payload (manifest + derived only).
public struct WatchViewUpdate: Codable, Equatable, Sendable {
    public var manifest: SessionManifest
    public var derived: DerivedSessionView

    public init(manifest: SessionManifest, derived: DerivedSessionView) {
        self.manifest = manifest
        self.derived = derived
    }
}

/// Watch-reported session versions for on-demand diff sync.
public struct WatchKnownSession: Codable, Equatable, Sendable {
    public var sessionId: String
    public var analyzerVersion: Int

    public init(sessionId: String, analyzerVersion: Int) {
        self.sessionId = sessionId
        self.analyzerVersion = analyzerVersion
    }
}

public struct WatchViewSyncReply: Equatable, Sendable {
    public var updates: [WatchViewUpdate]
    public var deletes: [String]

    public init(updates: [WatchViewUpdate], deletes: [String]) {
        self.updates = updates
        self.deletes = deletes
    }
}

/// Pure encode/decode for Watch Connectivity dictionaries.
public enum WatchViewSyncCodec {
    private static let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encodeViewUpdate(_ update: WatchViewUpdate) throws -> [String: Any] {
        [
            AppConstants.wcMessageTypeKey: WatchViewSyncMessageType.viewUpdate.rawValue,
            AppConstants.wcViewUpdateSessionIdKey: update.manifest.sessionId,
            AppConstants.wcViewUpdateManifestKey: try iso8601Encoder.encode(update.manifest).base64EncodedString(),
            AppConstants.wcViewUpdateDerivedKey: try iso8601Encoder.encode(update.derived).base64EncodedString(),
        ]
    }

    public static func encodeViewDelete(sessionId: String) -> [String: Any] {
        [
            AppConstants.wcMessageTypeKey: WatchViewSyncMessageType.viewDelete.rawValue,
            AppConstants.wcViewDeleteSessionIdKey: sessionId,
        ]
    }

    public static func encodeSyncRequest(known: [WatchKnownSession]) throws -> [String: Any] {
        let data = try iso8601Encoder.encode(known)
        return [
            AppConstants.wcMessageTypeKey: WatchViewSyncMessageType.syncRequest.rawValue,
            AppConstants.wcSyncKnownSessionsKey: data.base64EncodedString(),
        ]
    }

    public static func encodeSyncReply(_ reply: WatchViewSyncReply) throws -> [String: Any] {
        let updates = try reply.updates.map { try encodeViewUpdate($0) }
        return [
            AppConstants.wcMessageTypeKey: WatchViewSyncMessageType.syncReply.rawValue,
            AppConstants.wcSyncUpdatesKey: updates,
            AppConstants.wcSyncDeletesKey: reply.deletes,
        ]
    }

    public static func messageType(in message: [String: Any]) -> WatchViewSyncMessageType? {
        guard let raw = message[AppConstants.wcMessageTypeKey] as? String else { return nil }
        return WatchViewSyncMessageType(rawValue: raw)
    }

    public static func decodeViewUpdate(from message: [String: Any]) throws -> WatchViewUpdate? {
        guard messageType(in: message) == .viewUpdate else { return nil }
        guard
            let manifestBase64 = message[AppConstants.wcViewUpdateManifestKey] as? String,
            let derivedBase64 = message[AppConstants.wcViewUpdateDerivedKey] as? String,
            let manifestData = Data(base64Encoded: manifestBase64),
            let derivedData = Data(base64Encoded: derivedBase64)
        else {
            throw SessionStoreError.ioFailure("Invalid viewUpdate payload")
        }
        let manifest = try iso8601Decoder.decode(SessionManifest.self, from: manifestData)
        try SessionIdValidator.validate(manifest.sessionId)
        let derived = try iso8601Decoder.decode(DerivedSessionView.self, from: derivedData)
        return WatchViewUpdate(manifest: manifest, derived: derived)
    }

    public static func decodeViewDelete(from message: [String: Any]) throws -> String? {
        guard messageType(in: message) == .viewDelete else { return nil }
        guard let sessionId = message[AppConstants.wcViewDeleteSessionIdKey] as? String else {
            throw SessionStoreError.ioFailure("Invalid viewDelete payload")
        }
        try SessionIdValidator.validate(sessionId)
        return sessionId
    }

    public static func decodeSyncRequest(from message: [String: Any]) throws -> [WatchKnownSession]? {
        guard messageType(in: message) == .syncRequest else { return nil }
        guard
            let base64 = message[AppConstants.wcSyncKnownSessionsKey] as? String,
            let data = Data(base64Encoded: base64)
        else {
            throw SessionStoreError.ioFailure("Invalid syncRequest payload")
        }
        return try iso8601Decoder.decode([WatchKnownSession].self, from: data)
    }

    public static func decodeSyncReply(from message: [String: Any]) throws -> WatchViewSyncReply? {
        guard messageType(in: message) == .syncReply else { return nil }
        let deleteIds = (message[AppConstants.wcSyncDeletesKey] as? [String] ?? [])
            .filter { SessionIdValidator.isValid($0) }
        let rawUpdates = message[AppConstants.wcSyncUpdatesKey] as? [[String: Any]] ?? []
        var updates: [WatchViewUpdate] = []
        updates.reserveCapacity(rawUpdates.count)
        for item in rawUpdates {
            if let update = try decodeViewUpdate(from: item) {
                updates.append(update)
            }
        }
        return WatchViewSyncReply(updates: updates, deletes: deleteIds)
    }
}

public enum WatchViewSyncDiff {
    /// Builds phone reply: stale/missing updates + deletes for sessions gone on phone.
    public static func reply(
        knownOnWatch: [WatchKnownSession],
        phoneUpdates: [WatchViewUpdate]
    ) -> WatchViewSyncReply {
        let phoneById = Dictionary(uniqueKeysWithValues: phoneUpdates.map { ($0.manifest.sessionId, $0) })
        let phoneIds = Set(phoneById.keys)
        let knownById = Dictionary(uniqueKeysWithValues: knownOnWatch.map { ($0.sessionId, $0) })

        var updates: [WatchViewUpdate] = []
        updates.reserveCapacity(phoneUpdates.count)

        for update in phoneUpdates {
            let sessionId = update.manifest.sessionId
            guard update.manifest.transferState == .acknowledged else { continue }
            if let known = knownById[sessionId] {
                if known.analyzerVersion == update.derived.analyzerVersion {
                    continue
                }
            }
            updates.append(update)
        }

        let deletes = knownOnWatch
            .map(\.sessionId)
            .filter { !phoneIds.contains($0) }

        return WatchViewSyncReply(updates: updates, deletes: deletes)
    }
}
