import Foundation

/// Locale-aware meters / kilometers / speed display for Watch, Phone, and tests.
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

    /// Road-style kilometers (locale unit spelling / separators).
    public static func kilometers(_ meters: Double, locale: Locale = .current) -> String {
        let km = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .kilometers)
        let fractionLength: ClosedRange<Int> = km.value >= 10 ? 0...0 : 0...2
        return km.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionLength))
            )
            .locale(locale)
        )
    }

    /// Formats speed already expressed in km/h (detection / product unit).
    public static func kilometersPerHour(_ kmh: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(1...1))
            )
            .locale(locale)
        )
    }
}
