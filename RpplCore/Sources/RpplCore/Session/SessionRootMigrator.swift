import Foundation

/// One-shot package moves between session roots (App Group ↔ iCloud Documents).
/// Ongoing multi-device sync is Apple’s ubiquity file sync — not this type.
public enum SessionRootMigrator {
    public static func sessionIDs(
        in rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { SessionIdValidator.isValid($0) }
            .sorted()
    }

    public static func remoteOnlyIDs(local: Set<String>, remote: Set<String>) -> Set<String> {
        remote.subtracting(local)
    }

    public static func localOnlyIDs(local: Set<String>, remote: Set<String>) -> Set<String> {
        local.subtracting(remote)
    }

    /// Copies each session package directory from `sourceRoot` into `destinationRoot`
    /// when the destination does not already contain that session id.
    /// - Returns: session ids newly copied.
    @discardableResult
    public static func copyMissingPackages(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sourceIDs = try sessionIDs(in: sourceRoot, fileManager: fileManager)
        let destIDs = Set(try sessionIDs(in: destinationRoot, fileManager: fileManager))
        var copied: [String] = []
        for sessionId in sourceIDs where !destIDs.contains(sessionId) {
            guard SessionIdValidator.isValid(sessionId) else { continue }
            let source = sourceRoot.appendingPathComponent(sessionId, isDirectory: true)
            let dest = destinationRoot.appendingPathComponent(sessionId, isDirectory: true)
            try fileManager.copyItem(at: source, to: dest)
            copied.append(sessionId)
        }
        return copied.sorted()
    }

    /// Moves each session package from `sourceRoot` into `destinationRoot` (replacing if present).
    /// - Returns: session ids moved.
    @discardableResult
    public static func moveAllPackages(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sourceIDs = try sessionIDs(in: sourceRoot, fileManager: fileManager)
        var moved: [String] = []
        for sessionId in sourceIDs {
            guard SessionIdValidator.isValid(sessionId) else { continue }
            let source = sourceRoot.appendingPathComponent(sessionId, isDirectory: true)
            let dest = destinationRoot.appendingPathComponent(sessionId, isDirectory: true)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.moveItem(at: source, to: dest)
            moved.append(sessionId)
        }
        return moved.sorted()
    }

    /// Removes every session package under `rootURL` (and the root directory if empty-able).
    public static func removeAllPackages(
        at rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
    }
}
