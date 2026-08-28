import Foundation

public enum AppConstants {
    public static let appGroupID = "group.nl.dcsbl.rppl"
    /// iCloud Documents container (iPhone logbook when Drive sync is enabled).
    public static let iCloudContainerIdentifier = "iCloud.nl.dcsbl.rppl"
    public static let sessionsDirectoryName = "Sessions"
    public static let wcSessionFileMetaSessionID = "sessionId"
    public static let wcAckMessageKey = "ackSessionId"
    /// Discriminator for iPhone ↔ Watch logbook view sync (`viewUpdate`, `viewDelete`, …).
    public static let wcMessageTypeKey = "rpplMessageType"
    public static let wcViewUpdateSessionIdKey = "sessionId"
    public static let wcViewUpdateManifestKey = "manifestJSON"
    public static let wcViewUpdateDerivedKey = "derivedJSON"
    public static let wcViewDeleteSessionIdKey = "sessionId"
    public static let wcSyncKnownSessionsKey = "knownSessions"
    public static let wcSyncDeletesKey = "deletes"
    public static let wcSyncUpdatesKey = "updates"
    /// Opaque last-started activity code (`wakeboard`, …). Never a localized title.
    public static let lastActivityCodeDefaultsKey = "nl.dcsbl.rppl.lastActivityCode"
    public static let hkMetadataActivityCode = "nl.dcsbl.rppl.activityCode"

    public static var documentsSessionsRoot: URL {
        sessionsRoot(
            in: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        )
    }

    public static var appGroupSessionsRoot: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            .map { sessionsRoot(in: $0) }
    }

    /// App Group when available, else local Documents — phone fallback when Drive sync is off.
    public static var localPhoneSessionsRoot: URL {
        appGroupSessionsRoot ?? documentsSessionsRoot
    }

    /// `…/Documents/Sessions` inside an iCloud ubiquity container URL.
    public static func iCloudDocumentsSessionsRoot(containerURL: URL) -> URL {
        sessionsRoot(in: containerURL.appendingPathComponent("Documents", isDirectory: true))
    }

    public static func sessionsRoot(in baseURL: URL) -> URL {
        baseURL.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }
}
