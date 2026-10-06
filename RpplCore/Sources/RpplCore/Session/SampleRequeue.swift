import Foundation

/// What to do with a batch that could not be written (full disk, I/O error): put it back in
/// front of the samples that arrived since, so the next flush retries it — bounded, so a Watch
/// that stays full does not grow memory without end. When over the bound the oldest go first.
public enum SampleRequeue {
    public static func merge<Sample>(failed: [Sample], before pending: [Sample], cap: Int) -> [Sample] {
        let merged = failed + pending
        guard cap >= 0, merged.count > cap else { return merged }
        return Array(merged.suffix(cap))
    }

    /// Per-stream bounds, roughly an hour of each at its normal rate.
    public static let locationCap = 3_600
    public static let healthCap = 3_600
    public static let waterCap = 1_000
    public static let batteryCap = 500
    public static let altitudeCap = 3_600

    /// Below this much free space the Watch warns at Start.
    public static let lowStorageWarningBytes: Int64 = 200 * 1024 * 1024
}
