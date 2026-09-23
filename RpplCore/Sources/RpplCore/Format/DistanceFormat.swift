import Foundation

/// Locale-aware distance / speed display for Watch, Phone, and tests.
///
/// Inputs are always ISO (meters, km/h). The device measurement system (iOS Region /
/// Measurement System setting, surfaced via `Locale.measurementSystem`) only changes
/// what is shown: metric → m / km / km/h, US → ft / mi / mph, UK → yd / mi / mph.
public enum DistanceFormat {
    /// Short distance from meters (metric `m`, US `ft`, UK `yd`).
    public static func meters(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit: UnitLength
        switch locale.measurementSystem {
        case .us: unit = .feet
        case .uk: unit = .yards
        default: unit = .meters
        }
        return format(Measurement(value: value, unit: UnitLength.meters).converted(to: unit), fraction: 0...0, locale: locale)
    }

    /// Long distance from meters (metric `km`, US/UK `mi`).
    public static func kilometers(_ meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit: UnitLength = usesMiles(locale) ? .miles : .kilometers
        let converted = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
        let fraction: ClosedRange<Int> = converted.value >= 10 ? 0...0 : 0...2
        return format(converted, fraction: fraction, locale: locale)
    }

    /// Speed from km/h (detection / product unit); shown as km/h or mph per locale.
    public static func kilometersPerHour(_ kmh: Double, locale: Locale = .autoupdatingCurrent) -> String {
        format(speedMeasurement(kmh, locale: locale), fraction: 1...1, locale: locale)
    }

    /// Speed number only (no unit) for compact live tiles; pair with `speedUnitSymbol`.
    public static func speedValue(_ kmh: Double, locale: Locale = .autoupdatingCurrent) -> String {
        speedMeasurement(kmh, locale: locale).value.formatted(
            .number.precision(.fractionLength(0...0)).locale(locale)
        )
    }

    /// Localized speed unit symbol (`km/h` / `km/u`, `mph`).
    public static func speedUnitSymbol(locale: Locale = .autoupdatingCurrent) -> String {
        if usesMiles(locale) { return "mph" }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        return formatter.string(from: UnitSpeed.kilometersPerHour)
    }

    private static func usesMiles(_ locale: Locale) -> Bool {
        switch locale.measurementSystem {
        case .us, .uk: true
        default: false
        }
    }

    private static func speedMeasurement(_ kmh: Double, locale: Locale) -> Measurement<UnitSpeed> {
        let base = Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
        return usesMiles(locale) ? base.converted(to: .milesPerHour) : base
    }

    private static func format<U: Dimension>(
        _ measurement: Measurement<U>,
        fraction: ClosedRange<Int>,
        locale: Locale
    ) -> String {
        measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fraction))
            )
            .locale(locale)
        )
    }
}
