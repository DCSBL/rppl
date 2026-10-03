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
    /// Latest timestamp across the streams recorded before a crash: detections, GPS, health,
    /// water and battery. Motion is left out (large, and never later than GPS in practice).
    /// Unreadable streams count as empty. `nil` when nothing was recorded.
    public func lastRecordedTimestamp(sessionId: String) -> Date? {
        let detections = ((try? readDetections(sessionId: sessionId)) ?? []).map(\.timestamp)
        let locations = ((try? readLocationSamples(sessionId: sessionId)) ?? []).map(\.timestamp)
        let health = ((try? readHealthSamples(sessionId: sessionId)) ?? []).map(\.timestamp)
        let water = ((try? readWaterTemperatureSamples(sessionId: sessionId)) ?? []).map(\.timestamp)
        let battery = ((try? readBatterySamples(sessionId: sessionId)) ?? []).map(\.timestamp)
        return [detections.max(), locations.max(), health.max(), water.max(), battery.max()]
            .compactMap { $0 }
            .max()
    }

    /// Closes an orphaned recording: appends a terminal `inactive` marker, marks it ready to transfer
    /// and builds the derived view. Idempotent — non-recording sessions are left untouched.
    ///
    /// The session ends at the last recorded sample, not at the last detection event: events are
    /// sparse, so a `riding` enter minutes before the crash would otherwise get zero length and
    /// the final set (and everything recorded after it) would be clipped away.
    /// - Returns: `true` when the session was finalized by this call.
    @discardableResult
    public func finalizeOrphanedRecording(sessionId: String) throws -> Bool {
        let manifest = try readManifest(sessionId: sessionId)
        guard manifest.transferState == .recording else { return false }

        let endedAt = max(lastRecordedTimestamp(sessionId: sessionId) ?? manifest.startedAt, manifest.startedAt)

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
