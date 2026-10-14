import Foundation

/// Locale-aware duration words (hours / minutes / seconds) via Foundation format styles.
public enum DurationFormat {
    /// Wide or abbreviated unit labels that follow the active locale (e.g. `1 minute`, `2 minuten`).
    public static func units(
        _ interval: TimeInterval,
        width: Duration.UnitsFormatStyle.UnitWidth = .wide,
        locale: Locale = .current
    ) -> String {
        let clamped = max(0, interval)
        let duration = Duration.seconds(clamped)
        return duration.formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: width,
                maximumUnitCount: 3,
                zeroValueUnits: .hide
            )
            .locale(locale)
        )
    }

    /// Whole hours, minutes and seconds of `interval` (rounded), for columns that line up.
    public static func parts(_ interval: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int) {
        let total = Int(max(0, interval).rounded())
        return (total / 3600, total % 3600 / 60, total % 60)
    }
}
