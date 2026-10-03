import Foundation

/// Retry schedule for starting the HK workout after a sensors-only fallback.
///
/// A start timeout or error is not a denial: a busy `healthd` (older watches) often recovers
/// within minutes. Without a workout session the app has no background runtime, so keep trying.
public enum HealthKitRestartPolicy {
    public static let retryInterval: TimeInterval = 30
    public static let maxAttempts = 10

    /// - Parameter attempt: 1-based number of the retry about to run.
    public static func shouldRetry(attempt: Int, healthDenied: Bool) -> Bool {
        !healthDenied && attempt >= 1 && attempt <= maxAttempts
    }
}
