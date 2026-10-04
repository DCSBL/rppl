import Foundation

/// Format migrations for session packages. Empty at schema v1: the format was reset, so nothing
/// older exists. When `SessionSchema.currentVersion` is bumped, append a step that brings a
/// package from the previous version to the new one; `migrateIfNeeded` runs the steps in order
/// when a session is opened.
public enum SessionMigrations {
    public struct Step: Sendable {
        /// Version this step brings a package to.
        public let toVersion: Int
        public let run: @Sendable (_ store: SessionFileStore, _ sessionId: String) throws -> Void

        public init(
            toVersion: Int,
            run: @escaping @Sendable (_ store: SessionFileStore, _ sessionId: String) throws -> Void
        ) {
            self.toVersion = toVersion
            self.run = run
        }
    }

    public static let steps: [Step] = []

    /// Steps needed to go from `version` to `target`, in version order.
    public static func pending(from version: Int, to target: Int, in steps: [Step] = steps) -> [Step] {
        steps
            .filter { $0.toVersion > version && $0.toVersion <= target }
            .sorted { $0.toVersion < $1.toVersion }
    }
}

extension SessionFileStore {
    /// Brings a package below `currentVersion` up to it and stamps `manifest.schemaVersion`.
    /// - Returns: `true` when the package was migrated by this call.
    @discardableResult
    public func migrateIfNeeded(
        sessionId: String,
        currentVersion: Int = SessionSchema.currentVersion,
        steps: [SessionMigrations.Step] = SessionMigrations.steps
    ) throws -> Bool {
        let manifest = try readManifest(sessionId: sessionId)
        guard manifest.schemaVersion < currentVersion else { return false }
        for step in SessionMigrations.pending(from: manifest.schemaVersion, to: currentVersion, in: steps) {
            try step.run(self, sessionId)
        }
        // A step may have rewritten the manifest, so stamp the version on a fresh read.
        var updated = try readManifest(sessionId: sessionId)
        updated.schemaVersion = currentVersion
        try writeManifest(updated)
        return true
    }
}
