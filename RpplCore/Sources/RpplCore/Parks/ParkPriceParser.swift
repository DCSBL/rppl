import Foundation

/// Opaque values for `ParkPrice.per`: what an amount is charged for. Unknown values round-trip.
public enum ParkPriceUnit {
    public static let person = "person"
    public static let hour = "hour"
    public static let day = "day"
    public static let session = "session"

    public static let all = [person, hour, day, session]
}

public struct ParsedPrice: Equatable, Sendable {
    /// Negative for a discount.
    public var amount: Double
    /// ISO 4217 code when the text named one (`€`, `EUR`, `$`); nil when the person left it out.
    public var currency: String?
    /// A `ParkPriceUnit` when the text said "pp", "per hour", "/h", …
    public var per: String?

    public init(amount: Double, currency: String? = nil, per: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.per = per
    }
}

/// Reads a price the way people write it: `€12,34`, `12.50`, `€ 1.234,56`, `EUR 25`, `12,-`,
/// `-€3` (a discount), `€7 pp`, `€10 per hour`. Comma or dot as decimal mark, spaces and dots as
/// thousands marks. One price per text: `€5 / €7,50 / €10` is rejected so each gets its own row.
public enum ParkPriceParser {
    public enum Problem: Error, Equatable, Sendable {
        /// No digits, or something in between that is not part of a price.
        case unreadable
        /// More than one amount in one text.
        case severalAmounts
        case tooLarge
        case tooManyDecimals
    }

    public enum Result: Equatable, Sendable {
        case empty
        case price(ParsedPrice)
        case invalid(Problem)
    }

    public static let maxAmount = 100_000.0

    public static func parse(_ text: String) -> Result {
        var rest = normalize(text)
        if rest.isEmpty { return .empty }

        let unit = takeUnit(&rest)
        let currency = takeCurrency(&rest)
        rest = rest.trimmingCharacters(in: .whitespaces)

        // "12,-" and "12,=" are Dutch for twelve euros exactly.
        for suffix in [",-", ".-", ",--", ".--", ",=", ".="] where rest.hasSuffix(suffix) {
            rest = String(rest.dropLast(suffix.count)) + ".00"
            break
        }
        var negative = false
        rest = rest.trimmingCharacters(in: .whitespaces)
        while let sign = rest.first, sign == "-" || sign == "+" {
            if sign == "-" { negative.toggle() }
            rest.removeFirst()
            rest = rest.trimmingCharacters(in: .whitespaces)
        }
        if rest.isEmpty { return .invalid(.unreadable) }
        if rest.contains("/") || rest.contains(";") || rest.contains("&") { return .invalid(.severalAmounts) }
        guard let magnitude = number(from: rest) else {
            let hasSecondNumber = rest.split(separator: " ").filter { $0.first?.isNumber == true }.count > 1
            return .invalid(hasSecondNumber ? .severalAmounts : .unreadable)
        }
        switch magnitude {
        case .success(let value):
            if value > maxAmount { return .invalid(.tooLarge) }
            return .price(ParsedPrice(amount: negative ? -value : value, currency: currency, per: unit))
        case .failure(let problem):
            return .invalid(problem)
        }
    }

    // MARK: Number

    private static func number(from text: String) -> Swift.Result<Double, Problem>? {
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
        guard let value = Double(fraction.isEmpty ? integer : "\(integer).\(fraction)") else { return nil }
        return .success(value)
    }

    private static func thousandsGroupsAreValid(_ text: Substring, mark: Character) -> Bool {
        let groups = text.split(separator: mark, omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    // MARK: Currency and unit

    private static let symbols: [(token: String, code: String?)] = [
        ("€", "EUR"), ("$", "USD"), ("£", "GBP"), ("¥", "JPY"), ("zł", "PLN"), ("kč", "CZK"), ("kr.", nil), ("kr", nil),
    ]

    private static let isoCodes = Set(Locale.commonISOCurrencyCodes)

    private static func takeCurrency(_ text: inout String) -> String? {
        for (token, code) in symbols {
            if let range = text.range(of: token, options: .caseInsensitive) {
                text.removeSubrange(range)
                return code
            }
        }
        // Three letters, next to the number: "EUR 25", "25 chf".
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        for word in words where word.count == 3 && word.allSatisfy(\.isLetter) && isoCodes.contains(word.uppercased()) {
            if let range = text.range(of: word) {
                text.removeSubrange(range)
                return word.uppercased()
            }
        }
        return nil
    }

    private static let unitPatterns: [(unit: String, pattern: String)] = [
        (ParkPriceUnit.person, #"(?i)(\bp\.?\s?p\.?(?=\s|$)|\bper\s+(person|persoon|pers\.?|head)\b|/\s?(person|persoon|pp|p)\b)"#),
        (ParkPriceUnit.hour, #"(?i)(\bper\s+(hour|hr|uur|h)\b|/\s?(hour|hr|uur|h|u)\b)"#),
        (ParkPriceUnit.day, #"(?i)(\bper\s+(day|dag)\b|/\s?(day|dag|d)\b)"#),
        (ParkPriceUnit.session, #"(?i)(\bper\s+(session|sessie|keer|visit|bezoek)\b|/\s?(session|sessie|keer)\b)"#),
    ]

    private static func takeUnit(_ text: inout String) -> String? {
        for (unit, pattern) in unitPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                text.removeSubrange(range)
                return unit
            }
        }
        return nil
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

extension ParkPrice {
    /// The amount as an exact decimal, rounded to cents, for sums and averages.
    public var decimalAmount: Decimal? {
        guard let amount else { return nil }
        let cents = (amount * 100).rounded() / 100
        return Decimal(string: String(cents), locale: Locale(identifier: "en_US_POSIX"))
    }

    /// True for a discount (a negative amount, "-€3").
    public var isDiscount: Bool { (amount ?? 0) < 0 }

    /// What this price comes to per hour, when it says how long it covers (`minutes`) or is charged
    /// per hour. nil for prices that do not cover a duration (a day pass, a wristband).
    public var amountPerHour: Double? {
        guard let amount else { return nil }
        if let minutes, minutes > 0 { return amount * 60 / Double(minutes) }
        if per == ParkPriceUnit.hour { return amount }
        return nil
    }
}
