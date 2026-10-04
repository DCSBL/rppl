import Foundation

/// Which kind of text a park field holds. Decides the length limit and what is allowed in it.
public enum ParkTextField: Sendable, CaseIterable {
    /// Park name.
    case name
    /// Street address (may wrap over lines).
    case address
    /// Credit line.
    case author
    /// One short title: cable name, price name, block or rule label, link name.
    case label
    /// One facility ("Showers").
    case facility
    /// Phone number as typed.
    case phone
    case email
    case url
    /// Short remark on a rule, price, exception or the opening times.
    case note
    /// Cable description.
    case cableDescription
    /// Park description (light markdown allowed).
    case description

    /// Maximum length in characters (grapheme clusters), so an emoji or a flag counts as one.
    public var maxLength: Int {
        switch self {
        case .name: 80
        case .address: 200
        case .author: 60
        case .label: 60
        case .facility: 60
        case .phone: 32
        case .email: 120
        case .url: 500
        case .note: 300
        case .cableDescription: 400
        case .description: 1200
        }
    }

    public var allowsNewlines: Bool {
        switch self {
        case .address, .note, .cableDescription, .description: true
        default: false
        }
    }

    /// Italic, bold and lists work; headings do not. Not rendered yet, the text is stored as typed.
    public var allowsMarkdown: Bool {
        switch self {
        case .note, .cableDescription, .description: true
        default: false
        }
    }
}

/// How many items a list may hold, so a runaway paste cannot grow a file without bound.
public enum ParkLimits {
    public static let cables = 12
    public static let facilities = 40
    public static let rules = 40
    public static let slots = 60
    public static let prices = 60
    public static let links = 20
    public static let dates = 60
}

/// Cleans text typed or pasted into the park editor before it lands in a YAML file or a parser.
///
/// Anything a person may type stays: any script (including right-to-left), emoji and their joiners,
/// accents. What goes is what has no business in a name or a note: control characters, byte-order
/// marks, bidi overrides (they make text read differently than it is stored), line separators that
/// YAML treats as line breaks, private-use code points, and hidden tag characters. Over-long input
/// is cut at the field's limit.
public enum ParkText {
    /// Typing-time cleanup: strips unsafe characters and enforces the limit. Does not trim, so a
    /// space typed between two words survives.
    public static func sanitizeTyping(_ text: String, field: ParkTextField) -> String {
        truncate(strip(text, keepNewlines: field.allowsNewlines), to: field.maxLength)
    }

    /// Cleanup for storing: typing-time cleanup, trimmed, tidy blank lines, no headings in markdown
    /// fields. Empty becomes nil.
    public static func finalize(_ text: String?, field: ParkTextField) -> String? {
        guard let text else { return nil }
        var cleaned = sanitizeTyping(text, field: field)
        if field.allowsNewlines {
            var lines = cleaned.components(separatedBy: "\n").map { trimTrailing($0) }
            if field.allowsMarkdown { lines = lines.compactMap(removingHeading) }
            cleaned = collapseBlankLines(lines).joined(separator: "\n")
        } else {
            cleaned = collapseSpaces(cleaned)
        }
        cleaned = truncate(cleaned.trimmingCharacters(in: .whitespacesAndNewlines), to: field.maxLength)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Characters used in the text but over the limit, 0 when it fits. For "12 too long" hints.
    public static func overflow(_ text: String, field: ParkTextField) -> Int {
        max(0, text.count - field.maxLength)
    }

    // MARK: Contact values

    public enum ContactIssue: Equatable, Sendable {
        case tooFewDigits
        case tooManyDigits
        case badCharacters
        case missingAt
        case missingDomain
        case hasSpaces
        case notAWebAddress
    }

    /// `nil` when the phone number looks usable. Digits, spaces and `+ ( ) - . /` are accepted.
    public static func phoneIssue(_ phone: String) -> ContactIssue? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let allowed = Set("0123456789 +()-./")
        if trimmed.contains(where: { !allowed.contains($0) }) { return .badCharacters }
        let digits = trimmed.filter(\.isNumber).count
        if digits < 6 { return .tooFewDigits }
        if digits > 17 { return .tooManyDigits }
        return nil
    }

    /// `nil` when the address looks like an email address. Only the shape is checked.
    public static func emailIssue(_ email: String) -> ContactIssue? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(where: \.isWhitespace) { return .hasSpaces }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return .missingAt }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return .missingDomain }
        return nil
    }

    /// A web address ready to store: `https://` added when missing, only http(s), a host with a dot.
    /// `nil` when the text is not a web address at all.
    public static func normalizedWebAddress(_ text: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !candidate.contains(where: \.isWhitespace) else { return nil }
        if !candidate.contains("://") {
            // "mailto:", "javascript:" and friends are not web addresses; "site.nl:8080/menu" is.
            let beforePath = candidate.prefix { $0 != "/" }
            if let colon = beforePath.firstIndex(of: ":"), beforePath[beforePath.index(after: colon)...].first?.isNumber != true {
                return nil
            }
            candidate = "https://" + candidate
        }
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        return candidate.count <= ParkTextField.url.maxLength ? candidate : nil
    }

    // MARK: Cleanup details

    /// Drops scalars that do not belong in plain text. Emoji joiners, variation selectors, right-to-left
    /// marks and the tag characters of subdivision flags (🏴󠁧󠁢󠁳󠁣󠁴󠁿) are kept.
    private static func strip(_ text: String, keepNewlines: Bool) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{2029}", with: "\n")
        var result = ""
        for character in normalized {
            let scalars = character.unicodeScalars
            let isFlagSequence = scalars.first?.value == 0x1F3F4
            for scalar in scalars {
                if scalar == "\n" {
                    if keepNewlines { result.unicodeScalars.append(scalar) } else { result.append(" ") }
                } else if scalar == "\t" {
                    result.append(" ")
                } else if isAllowed(scalar, inFlagSequence: isFlagSequence) {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private static func isAllowed(_ scalar: Unicode.Scalar, inFlagSequence: Bool) -> Bool {
        let value = scalar.value
        switch value {
        case 0x00...0x1F, 0x7F...0x9F: return false
        case 0x202A...0x202E, 0x2066...0x2069: return false // bidi embeddings, overrides, isolates
        case 0xFEFF, 0xFFF9...0xFFFB, 0xFFFE, 0xFFFF: return false
        case 0xE000...0xF8FF, 0xF0000...0x10FFFF: return false // private use
        case 0xE0000...0xE007F: return inFlagSequence
        default: break
        }
        return !scalar.properties.isNoncharacterCodePoint
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }

    private static func trimTrailing(_ line: String) -> String {
        var line = line
        while line.last?.isWhitespace == true { line.removeLast() }
        return line
    }

    private static func collapseSpaces(_ text: String) -> String {
        var result = ""
        var lastWasSpace = false
        for character in text {
            if character == " " {
                if !lastWasSpace { result.append(character) }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result
    }

    /// No more than one blank line in a row, none at the start or end.
    private static func collapseBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result
    }

    /// Headings are not supported: `# Title` becomes `Title`, rules (`---`) and HTML tags go.
    /// `#hashtag` (no space) is not a heading and stays.
    private static func removingHeading(_ line: String) -> String? {
        let stripped = stripTags(line)
        let leading = stripped.prefix { $0 == " " }
        guard leading.count <= 3 else { return stripped }
        let body = stripped.dropFirst(leading.count)
        let hashes = body.prefix { $0 == "#" }
        if (1...6).contains(hashes.count) {
            let rest = body.dropFirst(hashes.count)
            if rest.isEmpty { return nil }
            if rest.first == " " {
                let text = rest.drop { $0 == " " }
                return String(text)
            }
        }
        let compact = body.filter { $0 != " " }
        if compact.count >= 3, let first = compact.first, "-=_*".contains(first), compact.allSatisfy({ $0 == first }) {
            return nil
        }
        return stripped
    }

    private static func stripTags(_ line: String) -> String {
        guard line.contains("<") else { return line }
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "<", let close = line[index...].firstIndex(of: ">") {
                let inner = line[line.index(after: index)..<close]
                let name = inner.drop { $0 == "/" }.first
                if name?.isLetter == true {
                    index = line.index(after: close)
                    continue
                }
            }
            result.append(line[index])
            index = line.index(after: index)
        }
        return result
    }
}
