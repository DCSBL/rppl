import Foundation

/// Pure helpers for infographic tiles: a big number with a small unit, and gauge fractions.
public enum MetricDisplay {
    public struct Parts: Equatable, Sendable {
        public let value: String
        public let unit: String?

        public init(value: String, unit: String?) {
            self.value = value
            self.unit = unit
        }
    }

    /// Splits a formatted measurement (`"42,2 km/h"`) into number and unit.
    ///
    /// Only a plain number followed by a digit-free unit is split. Anything else
    /// (`"1 h, 49 min"`, `"27%"`, `"--°"`) stays whole so it never renders half-styled.
    public static func split(_ formatted: String) -> Parts {
        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        let whole = Parts(value: trimmed, unit: nil)
        guard let gap = trimmed.lastIndex(where: \.isWhitespace) else { return whole }

        let number = trimmed[..<gap].trimmingCharacters(in: .whitespaces)
        let unit = trimmed[trimmed.index(after: gap)...]
        guard !number.isEmpty,
              !unit.isEmpty,
              number.contains(where: \.isNumber),
              number.allSatisfy(isNumberCharacter),
              !unit.contains(where: \.isNumber)
        else {
            return whole
        }
        return Parts(value: number, unit: String(unit))
    }

    /// `value / max` clamped to `0...1`; `0` for non-finite input or a non-positive max.
    public static func fraction(_ value: Double, of max: Double) -> Double {
        guard value.isFinite, max.isFinite, max > 0 else { return 0 }
        return Swift.min(Swift.max(value / max, 0), 1)
    }

    /// Position of `start...end` inside `lower...upper` as fractions of that range, for timelines.
    /// Clamped to `0...1`; an empty or inverted outer range gives `0...0`.
    public static func span(
        from start: Date,
        to end: Date,
        inRangeFrom lower: Date,
        to upper: Date
    ) -> ClosedRange<Double> {
        let total = upper.timeIntervalSince(lower)
        let a = fraction(start.timeIntervalSince(lower), of: total)
        let b = fraction(end.timeIntervalSince(lower), of: total)
        return Swift.min(a, b)...Swift.max(a, b)
    }

    private static func isNumberCharacter(_ character: Character) -> Bool {
        character.isNumber || character.isWhitespace || ".,'’+-−".contains(character)
    }
}
