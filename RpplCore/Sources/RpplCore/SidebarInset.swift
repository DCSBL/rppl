/// The free strip beside the app on iPhone Duo, where the buttons go.
///
/// It shows up as a trailing safe-area inset that the leading side does not have. Landscape iPhones
/// have a similar inset on both sides, so only a clearly lopsided one counts.
public enum SidebarInset {
    /// How much wider the trailing inset must be than the leading one (points).
    public static let minimumAsymmetry: Double = 30

    /// Width of the sidebar strip, or 0 when the window has none.
    public static func width(leading: Double, trailing: Double) -> Double {
        trailing - leading >= minimumAsymmetry ? trailing : 0
    }
}
