import Foundation

/// Finds and finalizes sessions left in `.recording` by a crash or kill.
/// Never deletes data; never resumes recording (see Docs/SessionStorage.md).
public enum SessionRecovery {
    /// Detector id on the terminal marker appended to a recovered session.
    public static let crashRecoveredDetectorId = "crash_recovered"

    /// Ids of `.recording` sessions other than the one currently being recorded.
    public static func orphanedRecordingIds(
        manifests: [SessionManifest],
        activeSessionId: String?
    ) -> [String] {
        manifests
            .filter { $0.transferState == .recording && $0.sessionId != activeSessionId }
            .map(\.sessionId)
    }
}

extension SessionFileStore {
    /// Closes an orphaned recording: appends a terminal `inactive` marker, marks it ready to transfer
    /// and builds the derived view. Idempotent — non-recording sessions are left untouched.
    /// - Returns: `true` when the session was finalized by this call.
    @discardableResult
    public func finalizeOrphanedRecording(sessionId: String) throws -> Bool {
        let manifest = try readManifest(sessionId: sessionId)
        guard manifest.transferState == .recording else { return false }

        let lastEventAt = try readDetections(sessionId: sessionId).map(\.timestamp).max()
        let endedAt = max(lastEventAt ?? manifest.startedAt, manifest.startedAt)

        try appendDetection(
            DetectionEvent(
                code: DetectionCodes.inactive,
                timestamp: endedAt,
                reason: SessionRecovery.crashRecoveredDetectorId,
                detectorId: SessionRecovery.crashRecoveredDetectorId
            ),
            sessionId: sessionId
        )
        try markReadyToTransfer(sessionId: sessionId, endedAt: endedAt)
        _ = try? ensureDerivedView(sessionId: sessionId)
        return true
    }

    /// Finalizes every orphaned recording; per-session failures are skipped so one bad package
    /// cannot block the rest. Returns the ids that were finalized.
    @discardableResult
    public func recoverOrphanedRecordings(activeSessionId: String?) -> [String] {
        let manifests = (try? listReadableManifests()) ?? []
        return SessionRecovery.orphanedRecordingIds(manifests: manifests, activeSessionId: activeSessionId)
            .filter { (try? finalizeOrphanedRecording(sessionId: $0)) == true }
    }
}
