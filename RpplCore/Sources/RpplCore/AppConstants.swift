import Foundation

public enum AppConstants {
    public static let prodAppGroupID = "group.nl.dcsbl.rppl"
    public static let prodICloudContainerIdentifier = "iCloud.nl.dcsbl.rppl"
    /// Info.plist keys the app targets fill from build settings. The side-by-side Dev variant
    /// points them at its own App Group and iCloud container (Docs/DevWorkflow.md).
    public static let appGroupInfoKey = "RpplAppGroupID"
    public static let iCloudContainerInfoKey = "RpplICloudContainerID"

    /// App Group shared by iPhone and Watch (Info.plist override, else prod).
    public static var appGroupID: String {
        resolvedIdentifier(
            infoValue: Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey),
            fallback: prodAppGroupID
        )
    }

    /// iCloud Documents container (iPhone logbook when Drive sync is enabled).
    public static var iCloudContainerIdentifier: String {
        resolvedIdentifier(
            infoValue: Bundle.main.object(forInfoDictionaryKey: iCloudContainerInfoKey),
            fallback: prodICloudContainerIdentifier
        )
    }

    /// Non-empty string wins; a missing key or unexpanded `$(…)` placeholder falls back to prod.
    public static func resolvedIdentifier(infoValue: Any?, fallback: String) -> String {
        guard let value = (infoValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("$(")
        else { return fallback }
        return value
    }

    /// Public TestFlight invite link. Opens the TestFlight join page for the Rppl beta.
    public static let betaJoinURL = URL(string: "https://testflight.apple.com/join/R2BymVaX")!
    public static let sessionsDirectoryName = "Sessions"
    /// User-added or edited park YAML files (override bundled parks with the same `id`).
    public static let parksDirectoryName = "Parks"
    /// Park editor work in progress, one JSON file per draft. Not park YAML: never read as a park.
    public static let parkDraftsDirectoryName = "ParkDrafts"
    public static let wcSessionFileMetaSessionID = "sessionId"
    public static let wcAckMessageKey = "ackSessionId"
    /// Phone → Watch: import of this session failed; the Watch keeps it and backs off.
    public static let wcNackMessageKey = "nackSessionId"
    public static let wcNackReasonKey = "nackReason"
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

    /// App Group container; Apple platforms only (no App Groups on Linux).
    private static var appGroupContainerURL: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        #else
        nil
        #endif
    }

    public static var appGroupSessionsRoot: URL? {
        appGroupContainerURL.map { sessionsRoot(in: $0) }
    }

    /// App Group when available, else local Documents — phone fallback when Drive sync is off.
    public static var localPhoneSessionsRoot: URL {
        appGroupSessionsRoot ?? documentsSessionsRoot
    }

    /// `…/Documents/Sessions` inside an iCloud ubiquity container URL.
    public static func iCloudDocumentsSessionsRoot(containerURL: URL) -> URL {
        sessionsRoot(in: containerURL.appendingPathComponent("Documents", isDirectory: true))
    }

    public static var localPhoneParksRoot: URL {
        let base = appGroupContainerURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(parksDirectoryName, isDirectory: true)
    }

    public static var localPhoneParkDraftsRoot: URL {
        let base = appGroupContainerURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(parkDraftsDirectoryName, isDirectory: true)
    }

    public static func sessionsRoot(in baseURL: URL) -> URL {
        baseURL.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }
}
