import Foundation

/// One-shot package moves between session roots (App Group ↔ iCloud Documents).
/// Ongoing multi-device sync is Apple’s ubiquity file sync — not this type.
public enum SessionRootMigrator {
    public static func sessionIDs(
        in rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        try SessionPackageLocator.sessionIDs(in: rootURL, fileManager: fileManager)
    }

    public static func remoteOnlyIDs(local: Set<String>, remote: Set<String>) -> Set<String> {
        remote.subtracting(local)
    }

    public static func localOnlyIDs(local: Set<String>, remote: Set<String>) -> Set<String> {
        local.subtracting(remote)
    }

    /// Copies each session package directory from `sourceRoot` into `destinationRoot`
    /// when the destination does not already contain that session id.
    /// Preserves human-readable folder names when possible.
    /// - Returns: session ids newly copied.
    @discardableResult
    public static func copyMissingPackages(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sourceIndex = try SessionPackageLocator.index(in: sourceRoot, fileManager: fileManager)
        let destIDs = Set(try sessionIDs(in: destinationRoot, fileManager: fileManager))
        var destNames = try SessionPackageLocator.existingFolderNames(
            in: destinationRoot,
            fileManager: fileManager
        )
        var copied: [String] = []
        for sessionId in sourceIndex.keys.sorted() where !destIDs.contains(sessionId) {
            guard SessionIdValidator.isValid(sessionId) else { continue }
            guard let entry = sourceIndex[sessionId] else { continue }
            let preferredName = entry.directoryURL.lastPathComponent
            let folderName: String
            if destNames.contains(preferredName) {
                folderName = SessionPackageNaming.uniqueFolderName(
                    base: preferredName,
                    existingNames: destNames
                )
            } else {
                folderName = preferredName
            }
            let dest = try SessionPackageNaming.packageDirectory(
                folderName: folderName,
                rootURL: destinationRoot
            )
            try fileManager.copyItem(at: entry.directoryURL, to: dest)
            destNames.insert(folderName)
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
        let sourceIndex = try SessionPackageLocator.index(in: sourceRoot, fileManager: fileManager)
        let destIndex = try SessionPackageLocator.index(in: destinationRoot, fileManager: fileManager)
        var destNames = try SessionPackageLocator.existingFolderNames(
            in: destinationRoot,
            fileManager: fileManager
        )
        var moved: [String] = []
        for sessionId in sourceIndex.keys.sorted() {
            guard SessionIdValidator.isValid(sessionId) else { continue }
            guard let entry = sourceIndex[sessionId] else { continue }
            if let existing = destIndex[sessionId] {
                try fileManager.removeItem(at: existing.directoryURL)
                destNames.remove(existing.directoryURL.lastPathComponent)
            }
            let preferredName = entry.directoryURL.lastPathComponent
            let folderName: String
            if destNames.contains(preferredName) {
                folderName = SessionPackageNaming.uniqueFolderName(
                    base: preferredName,
                    existingNames: destNames
                )
            } else {
                folderName = preferredName
            }
            let dest = try SessionPackageNaming.packageDirectory(
                folderName: folderName,
                rootURL: destinationRoot
            )
            try fileManager.moveItem(at: entry.directoryURL, to: dest)
            destNames.insert(folderName)
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
