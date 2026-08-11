import Foundation

/// Schema version for on-disk session packages. Bump when breaking changes land.
public enum SessionSchema {
    public static let currentVersion = 1
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
