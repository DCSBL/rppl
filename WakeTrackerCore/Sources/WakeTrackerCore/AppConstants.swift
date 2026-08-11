import Foundation

public enum AppConstants {
    public static let appGroupID = "group.nl.dcsbl.wake-tracker"
    public static let wcSessionFileMetaSessionID = "sessionId"
    public static let wcAckMessageKey = "ackSessionId"

    public static var documentsSessionsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Sessions", isDirectory: true)
    }

    public static var appGroupSessionsRoot: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Sessions", isDirectory: true)
    }
}
