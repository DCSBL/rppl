import Foundation

/// Schema version for on-disk session packages. Bump when breaking changes land.
public enum SessionSchema {
    /// v2: motion stored as framed zlib JSONL (`motion-NNN.jsonl.zlib`); transfer may carry `motionFramesZlib`.
    public static let currentVersion = 2
}

/// Coarse Action Button label codes (opaque strings — not a closed enum).
public enum LabelCodes {
    public static let waiting = "waiting"
    public static let riding = "riding"
    public static let swimming = "swimming"
    public static let walking = "walking"

    /// Cycle order for Ultra Action Button.
    public static let actionButtonCycle = [waiting, riding, swimming, walking]

    public static func next(after code: String) -> String {
        guard let index = actionButtonCycle.firstIndex(of: code) else {
            return actionButtonCycle[0]
        }
        return actionButtonCycle[(index + 1) % actionButtonCycle.count]
    }
}
