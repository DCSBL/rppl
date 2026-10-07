import Foundation

public struct ParsedAmount: Equatable, Sendable {
    /// Canonical exact text: `"25"`, `"12.50"`, `"-3"`.
    public var text: String
    public var value: Double

    public init(text: String, value: Double) {
        self.text = text
        self.value = value
    }
}

/// Reads an amount the way people type it: `12,34`, `12.34`, `1.234,56`, `1 234,50`, `12,-`, `-3`.
/// Comma or dot is the decimal mark, spaces and dots group thousands. A currency sign is ignored (the
/// currency has its own menu). One amount per text: `5 / 7,50` is rejected.
public enum ParkPriceParser {
    public enum Problem: Error, Equatable, Sendable {
        /// No digits, or something in between that is not part of an amount.
        case unreadable
        /// More than one amount in one text.
        case severalAmounts
        case tooLarge
        case tooManyDecimals
    }

    public enum Result: Equatable, Sendable {
        case empty
        case amount(ParsedAmount)
        case invalid(Problem)
    }

    public static let maxAmount = 100_000.0

    public static func parse(_ text: String) -> Result {
        var rest = normalize(text)
        for sign in ["€", "$", "£", "¥"] { rest = rest.replacingOccurrences(of: sign, with: "") }
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return .empty }

        // "12,-" and "12,=" are Dutch for twelve exactly.
        for suffix in [",--", ".--", ",-", ".-", ",=", ".="] where rest.hasSuffix(suffix) {
            rest = String(rest.dropLast(suffix.count)) + ".00"
            break
        }
        var negative = false
        while let sign = rest.first, sign == "-" || sign == "+" {
            if sign == "-" { negative.toggle() }
            rest.removeFirst()
            rest = rest.trimmingCharacters(in: .whitespaces)
        }
        if rest.isEmpty { return .invalid(.unreadable) }
        if rest.contains("/") || rest.contains(";") || rest.contains("&") { return .invalid(.severalAmounts) }
        guard let digits = number(from: rest) else {
            let second = rest.split(separator: " ").filter { $0.first?.isNumber == true }.count > 1
            return .invalid(second ? .severalAmounts : .unreadable)
        }
        switch digits {
        case .failure(let problem):
            return .invalid(problem)
        case .success(let parts):
            let canonical = canonicalText(integer: parts.integer, fraction: parts.fraction, negative: negative)
            guard let value = Double(canonical) else { return .invalid(.unreadable) }
            if abs(value) > maxAmount { return .invalid(.tooLarge) }
            return .amount(ParsedAmount(text: canonical, value: value))
        }
    }

    /// `25` → `"25"`, `12.5` → `"12.50"`.
    public static func canonicalText(for value: Double) -> String {
        let negative = value < 0
        let cents = Int((abs(value) * 100).rounded())
        return canonicalText(
            integer: String(cents / 100),
            fraction: String(format: "%02d", cents % 100),
            negative: negative
        )
    }

    private static func canonicalText(integer: String, fraction: String, negative: Bool) -> String {
        let whole = String(integer.drop { $0 == "0" })
        let trimmedFraction = fraction.padding(toLength: max(fraction.count, 2), withPad: "0", startingAt: 0)
        let isZeroFraction = trimmedFraction.allSatisfy { $0 == "0" }
        var text = whole.isEmpty ? "0" : whole
        if !isZeroFraction { text += "." + trimmedFraction.prefix(2) }
        let isZero = whole.isEmpty && isZeroFraction
        return negative && !isZero ? "-" + text : text
    }

    // MARK: Number

    private static func number(from text: String) -> Swift.Result<(integer: String, fraction: String), Problem>? {
        guard text.first?.isNumber == true, text.last?.isNumber == true else { return nil }
        let allowed = Set("0123456789.,' ")
        guard text.allSatisfy({ allowed.contains($0) }) else { return nil }

        var body = text
        if body.contains(" ") {
            // Spaces only group thousands: "1 234,50", not "5 7".
            let integerPart = body.prefix { $0 != "." && $0 != "," }
            let groups = integerPart.split(separator: " ", omittingEmptySubsequences: false)
            guard groups.count > 1, (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 })
            else { return nil }
            body = body.replacingOccurrences(of: " ", with: "")
        }
        body = body.replacingOccurrences(of: "'", with: "")

        let dots = body.filter { $0 == "." }.count
        let commas = body.filter { $0 == "," }.count
        var integer = body
        var fraction = ""
        if dots > 0, commas > 0 {
            // The mark that comes last is the decimal mark: "1.234,56" and "1,234.56".
            guard let last = body.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
            let decimal = body[last]
            let thousands: Character = decimal == "," ? "." : ","
            let head = body[..<last]
            guard !head.contains(decimal), thousandsGroupsAreValid(head, mark: thousands) else { return nil }
            integer = head.replacingOccurrences(of: String(thousands), with: "")
            fraction = String(body[body.index(after: last)...])
        } else if dots + commas == 1, let mark = body.firstIndex(where: { $0 == "." || $0 == "," }) {
            let head = body[..<mark]
            let tail = body[body.index(after: mark)...]
            if tail.count == 3, head.count <= 3, head != "0", !head.isEmpty {
                integer = String(head) + String(tail) // "1.234" is 1234, not 1.234
            } else {
                integer = String(head)
                fraction = String(tail)
            }
        } else if dots + commas > 1 {
            // Several of the same mark can only group thousands: "1.234.567".
            let mark: Character = dots > 0 ? "." : ","
            guard commas == 0 || dots == 0, thousandsGroupsAreValid(body[...], mark: mark) else { return nil }
            integer = body.replacingOccurrences(of: String(mark), with: "")
        }
        guard !integer.isEmpty, integer.allSatisfy(\.isNumber), fraction.allSatisfy(\.isNumber) else { return nil }
        if fraction.count > 2 { return .failure(.tooManyDecimals) }
        return .success((integer, fraction))
    }

    private static func thousandsGroupsAreValid(_ text: Substring, mark: Character) -> Bool {
        let groups = text.split(separator: mark, omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    private static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for space in ["\u{00A0}", "\u{2009}", "\u{202F}", "\u{2007}"] {
            result = result.replacingOccurrences(of: space, with: " ")
        }
        for minus in ["\u{2212}", "\u{2013}", "\u{2014}", "\u{2012}"] {
            result = result.replacingOccurrences(of: minus, with: "-")
        }
        return result
    }
}

extension ParkPriceOption {
    /// The amount as an exact decimal, for sums and averages.
    public var decimal: Decimal? {
        amount.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    public var value: Double? { amount.flatMap(Double.init) }

    /// True for a discount (a negative amount, "-3").
    public var isDiscount: Bool { (value ?? 0) < 0 }

    /// Nothing filled in yet.
    public var isBlank: Bool {
        (amount ?? "").isEmpty && (per?.text ?? "").isEmpty && (note?.text ?? "").isEmpty
    }
}
