import Foundation

/// A readable part of a source: a heading and the text under it.
public struct ParkSourceBlock: Equatable, Sendable {
    public var heading: String
    public var text: String

    public init(heading: String, text: String) {
        self.heading = heading
        self.text = text
    }
}

public struct ParkSourceLink: Equatable, Sendable {
    /// Absolute address.
    public var url: String
    public var label: String

    public init(url: String, label: String) {
        self.url = url
        self.label = label
    }
}

/// One source the person gave: a web page or the text read from a screenshot. Everything in it was
/// found by plain code; the language model only ever sees pieces of `blocks`.
public struct ParkSourcePage: Equatable, Sendable {
    /// Address of the page; a label for a screenshot.
    public var url: String
    public var title: String
    public var blocks: [ParkSourceBlock]
    public var links: [ParkSourceLink]
    public var phones: [String]
    public var emails: [String]
    /// `application/ld+json` blocks of the page (schema.org), as written.
    public var structuredData: [String]

    public init(
        url: String, title: String = "", blocks: [ParkSourceBlock] = [], links: [ParkSourceLink] = [],
        phones: [String] = [], emails: [String] = [], structuredData: [String] = []
    ) {
        self.url = url
        self.title = title
        self.blocks = blocks
        self.links = links
        self.phones = phones
        self.emails = emails
        self.structuredData = structuredData
    }

    /// Everything that can back up a value: the text, the link addresses, the phone numbers and emails.
    public var evidenceText: String {
        var parts = blocks.map { $0.heading.isEmpty ? $0.text : $0.heading + "\n" + $0.text }
        parts.append(contentsOf: links.map(\.url))
        parts.append(contentsOf: phones)
        parts.append(contentsOf: emails)
        parts.append(url)
        return parts.joined(separator: "\n")
    }
}

public enum ParkSourceExtractor {
    /// Reads a web page into blocks (cut at headings), links, phone numbers and emails.
    public static func extract(html: String, url: String) -> ParkSourcePage {
        let base = URL(string: url)
        var title = ""
        var description = ""
        var blocks: [ParkSourceBlock] = []
        var links: [ParkSourceLink] = []
        var phones: [String] = []
        var emails: [String] = []
        var heading = ""
        var headingText: String?
        var lines: [String] = []
        var line = ""
        var inTitle = false
        var navDepth = 0
        var anchor: (href: String, text: String)?

        func endLine() {
            let text = collapse(line)
            if !text.isEmpty { lines.append(text) }
            line = ""
        }
        func flushBlock() {
            endLine()
            if !lines.isEmpty { blocks.append(ParkSourceBlock(heading: heading, text: lines.joined(separator: "\n"))) }
            lines = []
        }

        for token in ParkHTML.tokens(html) {
            switch token {
            case .text(let raw):
                let text = ParkHTML.decode(raw)
                if inTitle {
                    title += text
                } else if headingText != nil {
                    headingText? += text
                } else if navDepth == 0 {
                    line += text
                }
                if anchor != nil { anchor?.text += text }
            case .open(let name, let attributes):
                switch name {
                case "title":
                    inTitle = true
                case "meta":
                    let key = (attributes["name"] ?? attributes["property"] ?? "").lowercased()
                    if key == "description" || key == "og:description" { description = attributes["content"] ?? description }
                case "nav":
                    endLine()
                    navDepth += 1
                case "a":
                    anchor = (attributes["href"] ?? "", "")
                case "td", "th":
                    if !collapse(line).isEmpty { line += " | " }
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flushBlock()
                    headingText = ""
                default:
                    if blockTags.contains(name) { endLine() }
                }
            case .close(let name):
                switch name {
                case "title":
                    inTitle = false
                case "nav":
                    navDepth = max(navDepth - 1, 0)
                case "a":
                    if let current = anchor {
                        anchor = nil
                        let label = collapse(current.text)
                        let href = current.href.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lowered = href.lowercased()
                        if lowered.hasPrefix("tel:") {
                            phones.append(String(href.dropFirst(4)))
                        } else if lowered.hasPrefix("mailto:") {
                            let address = href.dropFirst(7).split(separator: "?").first.map(String.init) ?? ""
                            if ParkText.emailIssue(address) == nil, !address.isEmpty { emails.append(address) }
                        } else if let resolved = resolve(href, base: base), !links.contains(where: { $0.url == resolved }) {
                            links.append(ParkSourceLink(url: resolved, label: label))
                        }
                    }
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    if let text = headingText {
                        heading = collapse(text)
                        headingText = nil
                    }
                default:
                    if blockTags.contains(name) { endLine() }
                }
            }
        }
        flushBlock()
        let summary = collapse(description)
        if !summary.isEmpty { blocks.insert(ParkSourceBlock(heading: "", text: summary), at: 0) }

        let text = blocks.map(\.text).joined(separator: "\n")
        // Written out in the text is how people read them, so those come before the bare `tel:` and `mailto:` values.
        return ParkSourcePage(
            url: url, title: collapse(title), blocks: blocks, links: links,
            phones: unique(ParkSourceFacts.phones(in: text) + phones),
            emails: unique(ParkSourceFacts.emails(in: text) + emails),
            structuredData: ParkStructuredHours.jsonLDBlocks(inHTML: html)
        )
    }

    /// Text read from a screenshot: paragraphs (cut at blank lines) become blocks.
    public static func extract(plainText: String, label: String) -> ParkSourcePage {
        var blocks: [ParkSourceBlock] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { blocks.append(ParkSourceBlock(heading: "", text: current.joined(separator: "\n"))) }
            current = []
        }
        for raw in plainText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = collapse(String(raw))
            if line.isEmpty { flush() } else { current.append(line) }
        }
        flush()
        return ParkSourcePage(
            url: label, blocks: blocks,
            phones: ParkSourceFacts.phones(in: plainText), emails: ParkSourceFacts.emails(in: plainText)
        )
    }

    // MARK: Helpers

    private static let blockTags: Set<String> = [
        "p", "div", "li", "ul", "ol", "tr", "table", "br", "section", "article", "header", "footer", "main",
        "aside", "address", "dd", "dt", "dl", "form", "blockquote", "figure", "figcaption",
    ]

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "@" }).inserted }
    }

    static func resolve(_ href: String, base: URL?) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.lowercased().hasPrefix("javascript:") else { return nil }
        guard let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)
        parts?.fragment = nil
        return parts?.string ?? url.absoluteString
    }
}

/// Facts that are recognised by their shape, so no model is needed for them.
public enum ParkSourceFacts {
    private static let imageSuffixes = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]

    public static func emails(in text: String) -> [String] {
        var found: [String] = []
        let separators = Set("<>()[],;:\"'|")
        for line in text.split(whereSeparator: \.isNewline) {
            for token in line.split(whereSeparator: { $0.isWhitespace || separators.contains($0) }) where token.contains("@") {
                var email = String(token)
                while let last = email.last, last == "." || last == "-" { email.removeLast() }
                let lowered = email.lowercased()
                guard ParkText.emailIssue(email) == nil, let at = email.firstIndex(of: "@"),
                      email[email.index(after: at)...].contains("."),
                      !imageSuffixes.contains(where: { lowered.hasSuffix($0) }) else { continue }
                if !found.contains(where: { $0.lowercased() == lowered }) { found.append(email) }
            }
        }
        return found
    }

    /// Phone numbers as written, nine to fifteen digits. A run of digits glued to letters (a VAT or
    /// chamber of commerce number) is not a phone number.
    public static func phones(in text: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        let allowed = Set("0123456789 +()-./")
        for line in text.split(whereSeparator: \.isNewline) {
            var run = ""
            var tainted = false
            var previous: Character?

            func finish() {
                defer {
                    run = ""
                    tainted = false
                }
                let trimmed = run.trimmingCharacters(in: CharacterSet(charactersIn: " ./-)"))
                let digits = trimmed.filter { $0.isASCII && $0.isNumber }
                guard !tainted, (9...15).contains(digits.count), let first = trimmed.first,
                      first.isNumber || first == "+" || first == "(", !trimmed.contains("..") else { return }
                if seen.insert(digits).inserted { found.append(ParkSourceExtractor.collapse(trimmed)) }
            }

            for char in line {
                if allowed.contains(char) {
                    if char.isNumber, previous?.isLetter == true, !run.contains(where: \.isNumber) { tainted = true }
                    run.append(char)
                } else {
                    finish()
                }
                previous = char
            }
            finish()
        }
        return found
    }
}
