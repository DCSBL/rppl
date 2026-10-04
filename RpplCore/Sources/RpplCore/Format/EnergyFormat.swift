import Foundation

// Apple-only: `FormatStyle` / `MeasurementFormatter` are unavailable in Linux Foundation.
#if canImport(Darwin)

/// Locale-aware energy display (HealthKit kcal mirrored into session stats).
public enum EnergyFormat {
    public static func kilocalories(_ value: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: value, unit: UnitEnergy.kilocalories)
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
#endif
