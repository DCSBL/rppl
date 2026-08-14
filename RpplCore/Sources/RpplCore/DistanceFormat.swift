import Foundation

/// Locale-aware meters display for Watch, Phone, and tests.
public enum DistanceFormat {
    /// Formats a distance in meters using the given locale (e.g. Dutch grouping `1.234 m`).
    public static func meters(_ value: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: value, unit: UnitLength.meters)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...0))
            )
            .locale(locale)
        )
    }
}
