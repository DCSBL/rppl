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

    /// `isCompactWidthClass` is the system's own verdict that a `NavigationSplitView` collapses into one
    /// stack (most iPhones in landscape are wider than the minimum but still compact): the detail column
    /// is then unreachable, so it must not be treated as two panes.
    public static func resolve(
        width: Double,
        isAccessibilityTextSize: Bool,
        isCompactWidthClass: Bool = false
    ) -> WindowLayout {
        if isCompactWidthClass { return .stack }
        let minimum = isAccessibilityTextSize ? twoPaneMinWidthAccessibility : twoPaneMinWidth
        return width >= minimum ? .twoPane : .stack
    }

    /// Whether the sidebar column shows the map in place of its list. Only the system's own collapsed
    /// verdict (compact width class) decides, not the measured width: while a fold or resize is animating, the
    /// width crosses `twoPaneMinWidth` before the split view collapses or expands, and swapping a list for an
    /// `MKMapView` inside that scene update made the map re-inset on every layout pass until the watchdog
    /// killed the app (iPhone Duo, half-fold).
    public static func sidebarHostsMap(wantsMap: Bool, isCompactWidthClass: Bool) -> Bool {
        wantsMap && isCompactWidthClass
    }
}
