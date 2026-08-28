import Foundation

public enum SessionIdValidator {
    /// Rejects path separators and parent-directory segments before any file URL is built.
    public static func validate(_ sessionId: String) throws {
        guard !sessionId.isEmpty else {
            throw SessionStoreError.invalidSessionId(sessionId)
        }
        if sessionId.contains("/") || sessionId.contains("\\") {
            throw SessionStoreError.invalidSessionId(sessionId)
        }
        if sessionId.contains("..") {
            throw SessionStoreError.invalidSessionId(sessionId)
        }
    }

    public static func isValid(_ sessionId: String) -> Bool {
        (try? validate(sessionId)) != nil
    }

    /// Session package directory guaranteed to stay under `rootURL`.
    public static func sessionDirectory(for sessionId: String, rootURL: URL) throws -> URL {
        try validate(sessionId)
        let root = rootURL.standardizedFileURL
        let resolved = root.appendingPathComponent(sessionId, isDirectory: true).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(rootPrefix) else {
            throw SessionStoreError.invalidSessionId(sessionId)
        }
        return resolved
    }
}
