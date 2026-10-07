import Foundation

// Apple-only: `FormatStyle` / `MeasurementFormatter` are unavailable in Linux Foundation.
#if canImport(Darwin)

/// Session water-temperature display. Input is always °C; output follows the device
/// temperature unit (°C / °F). Placeholder until first sample.
public enum TemperatureFormat {
    public static let placeholder = "--°"

    public static func celsius(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: value, unit: UnitTemperature.celsius).formatted(
            .measurement(
                width: .abbreviated,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0...0))
            )
            .locale(locale)
        )
    }

    /// "14° – 19°" (each end follows the device unit).
    public static func celsiusRange(_ range: ClosedRange<Double>, locale: Locale = .autoupdatingCurrent) -> String {
        "\(celsius(range.lowerBound, locale: locale)) – \(celsius(range.upperBound, locale: locale))"
    }
}
#endif
