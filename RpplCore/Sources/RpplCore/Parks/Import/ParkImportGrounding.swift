import Foundation

/// Checks what the model wrote against what it was given. A small on-device model sometimes makes
/// things up; a value that cannot be found in the source is flagged, so a person never accepts it blind.
public struct ParkImportGrounding: Sendable {
    public enum Level: Int, Comparable, Sendable {
        /// Not found anywhere in the source.
        case notFound
        /// The value is in the source, but not in the words the model quoted for it.
        case weak
        /// The model's quote is in the source and the value is in the quote.
        case verified

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private let lowered: String
    private let words: String
    private let numbers: [Double]
    private let phoneEnds: Set<String>

    public init(sourceText: String) {
        lowered = sourceText.lowercased()
        words = Self.words(in: sourceText)
        numbers = Self.numbers(in: sourceText)
        phoneEnds = Set(ParkSourceFacts.phones(in: sourceText).map { Self.phoneEnd($0) })
    }

    public init(pages: [ParkSourcePage]) {
        self.init(sourceText: pages.map(\.evidenceText).joined(separator: "\n"))
    }

    /// A price amount; `quote` is what the model says it read it from.
    public func amount(_ amount: String, quote: String?) -> Level {
        guard case .amount(let parsed) = ParkPriceParser.parse(amount) else { return .notFound }
        let quoted = Self.words(in: quote ?? "")
        if quoted.count >= 3, words.contains(quoted), Self.numbers(in: quote ?? "").contains(where: { Self.same($0, parsed.value) }) {
            return .verified
        }
        return numbers.contains(where: { Self.same($0, parsed.value) }) ? .weak : .notFound
    }

    /// Any short text, found literally (not counting case, accents and punctuation).
    public func text(_ text: String) -> Bool {
        let wanted = Self.words(in: text)
        return !wanted.isEmpty && words.contains(wanted)
    }

    public func phone(_ phone: String) -> Bool {
        let end = Self.phoneEnd(phone)
        return end.count >= 6 && phoneEnds.contains(end)
    }

    public func email(_ email: String) -> Bool {
        let wanted = email.lowercased()
        return !wanted.isEmpty && lowered.contains(wanted)
    }

    public func url(_ url: String) -> Bool {
        let wanted = ParkImportCrawler.normalized(url)
        return !wanted.isEmpty && lowered.contains(wanted)
    }

    // MARK: Reading

    /// Lowercase words without accents and punctuation, one space between them, a space at both ends.
    static func words(in text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var result = " "
        for char in folded {
            if char.isLetter || char.isNumber {
                result.append(char)
            } else if result.last != " " {
                result.append(" ")
            }
        }
        if result.last != " " { result.append(" ") }
        return result
    }

    /// Every number in the text as a value: `12,50`, `12.50`, `1.234,50`, `12,-` all read as numbers.
    static func numbers(in text: String) -> [Double] {
        var values: [Double] = []
        var run = ""
        func finish() {
            while let last = run.last, last == "," || last == "." { run.removeLast() }
            if !run.isEmpty, case .amount(let parsed) = ParkPriceParser.parse(run) { values.append(parsed.value) }
            run = ""
        }
        for char in text {
            if char.isASCII, char.isNumber {
                run.append(char)
            } else if (char == "," || char == "."), !run.isEmpty {
                run.append(char)
            } else {
                finish()
            }
        }
        finish()
        return values
    }

    private static func same(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.005 }

    /// The last nine digits: the same number written with or without country code compares equal.
    private static func phoneEnd(_ phone: String) -> String {
        String(phone.filter { $0.isASCII && $0.isNumber }.suffix(9))
    }
}
