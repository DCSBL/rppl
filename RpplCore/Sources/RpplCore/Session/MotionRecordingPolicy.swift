import Foundation

/// Device motion is the first stream to give way. Nothing analyses it yet — it is kept for future
/// trick / event analysis — so when a session runs long, the motion file grows large, or the Watch
/// runs out of space, motion stops (or is deleted) before GPS, detection, health or water are
/// touched.
public enum MotionRecordingPolicy {
    public enum Decision: Equatable, Sendable {
        case record
        /// Stop recording motion; keep what is already on disk.
        case stop(reason: String)
        /// Stop and delete this session's motion to free space for the streams that matter.
        case dropRecorded(reason: String)

        public var reason: String? {
            switch self {
            case .record: return nil
            case .stop(let reason), .dropRecorded(let reason): return reason
            }
        }
    }

    /// Opaque codes written to `SessionManifest.motionStoppedReason`.
    public enum Reason {
        public static let longSession = "long_session"
        public static let fileBudget = "file_budget"
        public static let lowStorage = "low_storage"
        public static let storageCritical = "storage_critical"
    }

    /// A day pass keeps its first hours of motion; the rest of the day records without it.
    public static let maxSessionDuration: TimeInterval = 4 * 3600
    /// Compressed motion bytes per session. ~15 MB decodes to under the 64 MB import bound.
    public static let maxCompressedBytes: Int64 = 15 * 1024 * 1024
    /// Below this much free space no new motion is written.
    public static let stopBelowFreeBytes: Int64 = 300 * 1024 * 1024
    /// Below this, the session's motion is deleted too.
    public static let dropBelowFreeBytes: Int64 = 100 * 1024 * 1024
    /// Motion is written as one compressed frame per interval instead of one per 2 s flush, so a
    /// long session stays far below `CompressedJSONLFrames.maxFrameCount`.
    public static let frameInterval: TimeInterval = 30

    /// - Parameters:
    ///   - elapsed: recorded session time (product pauses excluded).
    ///   - motionBytes: compressed motion already on disk for this session.
    ///   - freeBytes: free space on the volume; nil when unknown (never stops motion by itself).
    public static func decide(elapsed: TimeInterval, motionBytes: Int64, freeBytes: Int64?) -> Decision {
        if let freeBytes, freeBytes < dropBelowFreeBytes {
            return .dropRecorded(reason: Reason.storageCritical)
        }
        if let freeBytes, freeBytes < stopBelowFreeBytes {
            return .stop(reason: Reason.lowStorage)
        }
        if motionBytes >= maxCompressedBytes {
            return .stop(reason: Reason.fileBudget)
        }
        if elapsed >= maxSessionDuration {
            return .stop(reason: Reason.longSession)
        }
        return .record
    }
}
