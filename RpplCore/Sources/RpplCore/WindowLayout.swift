/// Chooses between the single-column phone layout and a sidebar plus detail layout.
///
/// Driven only by the width the window really has and the text size, never by device, idiom or
/// orientation: iPhone Duo (and iPad, iPhone Mirroring, split windows) resize live.
public enum WindowLayout: Equatable, Sendable {
    case stack
    case twoPane

    /// Narrowest window (points) that gets two panes at normal text sizes.
    public static let twoPaneMinWidth: Double = 520

    /// Accessibility text sizes need more room: a sidebar at these sizes leaves no space for the detail.
    public static let twoPaneMinWidthAccessibility: Double = 760

    public static func resolve(width: Double, isAccessibilityTextSize: Bool) -> WindowLayout {
        let minimum = isAccessibilityTextSize ? twoPaneMinWidthAccessibility : twoPaneMinWidth
        return width >= minimum ? .twoPane : .stack
    }
}
