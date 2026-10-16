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

    /// One rounded unit (`37 hr`, `40 min`) so a long total fits a narrow tile and splits into number + unit.
    /// `fractionDigits` > 0 keeps decimals (`37.5 hr`) for the logbook totals.
    public static func total(_ interval: TimeInterval, fractionDigits: Int = 0, locale: Locale = .current) -> String {
        let unit: Duration.UnitsFormatStyle.Unit = interval >= 3600 ? .hours : .minutes
        return Duration.seconds(max(0, interval)).formatted(
            .units(
                allowed: [unit],
                width: .abbreviated,
                fractionalPart: fractionDigits > 0
                    ? .show(length: fractionDigits, rounded: .toNearestOrAwayFromZero)
                    : .hide(rounded: .toNearestOrAwayFromZero)
            )
            .locale(locale)
        )
    }

    public struct Parts: Equatable, Sendable {
        public let hours: Int
        public let minutes: Int
        public let seconds: Int
    }

    /// Whole hours, minutes and seconds of `interval` (rounded), for columns that line up.
    public static func parts(_ interval: TimeInterval) -> Parts {
        let total = Int(max(0, interval).rounded())
        return Parts(hours: total / 3600, minutes: total % 3600 / 60, seconds: total % 60)
    }
}
