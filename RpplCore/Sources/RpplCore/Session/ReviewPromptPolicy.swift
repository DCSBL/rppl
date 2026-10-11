import Foundation

/// When to ask for an App Store rating. StoreKit never reports whether the sheet was shown or what
/// the rider did, so the schedule is fixed: the 3rd and 10th good session, then every 10th.
public struct ReviewPromptState: Codable, Equatable, Sendable {
    /// Ids of good sessions seen so far; a set so reloads and re-imports never double count.
    public private(set) var countedSessionIDs: Set<String>
    /// Highest milestone already armed (0 = none).
    public private(set) var promptedMilestone: Int
    /// A milestone was reached and the prompt has not been requested yet.
    public private(set) var pending: Bool

    public init(countedSessionIDs: Set<String> = [], promptedMilestone: Int = 0, pending: Bool = false) {
        self.countedSessionIDs = countedSessionIDs
        self.promptedMilestone = promptedMilestone
        self.pending = pending
    }

    public static let minimumDuration: TimeInterval = 30 * 60
    public static let minimumSetsWithLap = 3

    /// Tracked session of at least 30 minutes with at least 3 sets that each have a lap.
    public static func isGoodSession(manifest: SessionManifest, stats: SessionStats) -> Bool {
        guard manifest.manual == nil, stats.totalDuration >= minimumDuration else { return false }
        return stats.sets.filter { $0.lapCount >= 1 }.count >= minimumSetsWithLap
    }

    /// Milestone reached at `count` good sessions: 0 below 3, then 3, 10, 20, 30, …
    public static func milestone(for count: Int) -> Int {
        switch count {
        case ..<3: 0
        case 3..<10: 3
        case 10..<20: 10
        default: count / 10 * 10
        }
    }

    /// Adds sessions; returns true when this call armed a new prompt.
    @discardableResult
    public mutating func record(goodSessionIDs: some Sequence<String>) -> Bool {
        countedSessionIDs.formUnion(goodSessionIDs)
        let reached = Self.milestone(for: countedSessionIDs.count)
        guard reached > promptedMilestone else { return false }
        promptedMilestone = reached
        pending = true
        return true
    }

    /// True once per armed milestone; clears the flag.
    public mutating func consumePending() -> Bool {
        defer { pending = false }
        return pending
    }
}
