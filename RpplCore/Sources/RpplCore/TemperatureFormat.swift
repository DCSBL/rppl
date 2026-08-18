import Foundation

/// Session water-temperature display (`22 C`; placeholder `- C` until first sample).
public enum TemperatureFormat {
    public static let placeholder = "- C"

    public static func celsius(_ value: Double, locale: Locale = .current) -> String {
        let number = value.formatted(
            .number.precision(.fractionLength(0...1)).locale(locale)
        )
        return "\(number) C"
    }
}
