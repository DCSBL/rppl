import Foundation

/// What the import looks for. A closed list: the model is only ever asked about these, never an
/// open question, so it cannot wander off the park's domain.
public enum ParkImportTopic: String, CaseIterable, Sendable {
    case prices
    case contact
    case facilities
    /// Read by code (`ParkOpeningReader`), never by the model.
    case opening
    /// Read by code (`ParkEventReader`), never by the model.
    case events

    /// The topics the model is asked about.
    public static let modelTopics: [ParkImportTopic] = [.prices, .contact, .facilities]

    /// Lowercase words (Dutch, German, English, French) that mark a heading, link or address as this topic.
    var keywords: [String] {
        switch self {
        case .prices:
            ["prijs", "prijzen", "tarief", "tarieven", "kosten", "tickets", "ticket", "abonnement", "preis", "preise",
             "eintritt", "gebühr", "tarife", "price", "pricing", "rates", "admission", "prix", "tarif"]
        case .contact:
            ["contact", "kontakt", "bereikbaar", "anschrift", "address", "anfahrt", "route", "find us"]
        case .facilities:
            ["faciliteiten", "voorzieningen", "facilities", "ausstattung", "einrichtungen", "équipements", "amenities"]
        case .opening:
            ["openingstij", "geopend", "öffnungszeit", "oeffnungszeit", "opening hours", "opening-hours", "opening times",
             "horaires", "wanneer open", "hours"]
        case .events:
            ["agenda", "evenement", "event", "veranstaltung", "kalender", "calendar", "activiteit", "nieuws", "news",
             "actueel", "aktuell", "wedstrijd", "competition"]
        }
    }

    func matches(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { lowered.contains($0) }
    }
}

/// A piece of source text small enough for the on-device model (4096 tokens per session, shared with
/// the instructions, the schema and the answer).
public struct ParkImportChunk: Equatable, Sendable, Identifiable {
    public var topic: ParkImportTopic
    public var index: Int
    public var text: String

    public var id: String { "\(topic.rawValue)-\(index)" }
}

public enum ParkImportChunker {
    /// About 800 to 1000 tokens of Dutch or German text, which leaves room for the rest.
    public static let maxCharacters = 2400
    public static let maxChunksPerTopic = 3

    /// The topics a block is about, judged by its heading and by what is in it.
    public static func topics(of block: ParkSourceBlock) -> Set<ParkImportTopic> {
        var result = Set<ParkImportTopic>()
        let lowered = block.text.lowercased()
        if ParkImportTopic.prices.matches(block.heading) || lowered.contains("€") || lowered.contains(" eur") {
            result.insert(.prices)
        }
        if ParkImportTopic.contact.matches(block.heading)
            || !ParkSourceFacts.emails(in: block.text).isEmpty || !ParkSourceFacts.phones(in: block.text).isEmpty {
            result.insert(.contact)
        }
        if ParkImportTopic.facilities.matches(block.heading) { result.insert(.facilities) }
        if ParkImportTopic.opening.matches(block.heading) || ParkImportTopic.opening.matches(block.text)
            && !ParkOpeningReader.timeRanges(in: block.text).isEmpty {
            result.insert(.opening)
        }
        return result
    }

    /// Sorts what the pages say into chunks per topic, in page order.
    public static func chunks(for pages: [ParkSourcePage], topics: [ParkImportTopic] = ParkImportTopic.modelTopics) -> [ParkImportChunk] {
        var result: [ParkImportChunk] = []
        for topic in topics {
            var pieces: [String] = []
            for page in pages {
                for block in page.blocks where self.topics(of: block).contains(topic) {
                    let text = block.heading.isEmpty ? block.text : block.heading + "\n" + block.text
                    pieces.append(contentsOf: split(text))
                }
            }
            var packed: [String] = []
            var current = ""
            for piece in pieces {
                if !current.isEmpty, current.count + piece.count + 2 > maxCharacters {
                    packed.append(current)
                    current = ""
                }
                current += current.isEmpty ? piece : "\n\n" + piece
            }
            if !current.isEmpty { packed.append(current) }
            for (index, text) in packed.prefix(maxChunksPerTopic).enumerated() {
                result.append(ParkImportChunk(topic: topic, index: index, text: text))
            }
        }
        return result
    }

    /// A piece longer than the budget is cut at line breaks.
    private static func split(_ text: String) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var parts: [String] = []
        var current = ""
        for line in text.split(separator: "\n") {
            let line = String(line.prefix(maxCharacters))
            if !current.isEmpty, current.count + line.count + 1 > maxCharacters {
                parts.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

/// Finds the pages of the same site that probably hold what a page did not. Never leaves the site.
public enum ParkImportCrawler {
    private static let skippedSuffixes = [
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".pdf", ".zip", ".mp4", ".mp3", ".css", ".js", ".ics",
    ]

    /// Same-site links whose address or label names one of `topics`, best match first, not yet in `visited`.
    public static func candidates(
        from page: ParkSourcePage, topics: [ParkImportTopic], visited: Set<String>
    ) -> [ParkSourceLink] {
        guard let host = siteHost(page.url), !topics.isEmpty else { return [] }
        let seen = Set(visited.map(normalized))
        var scored: [(link: ParkSourceLink, score: Int)] = []
        for link in page.links {
            guard siteHost(link.url) == host, !seen.contains(normalized(link.url)),
                  !skippedSuffixes.contains(where: { link.url.lowercased().split(separator: "?")[0].hasSuffix($0) }),
                  !scored.contains(where: { normalized($0.link.url) == normalized(link.url) }) else { continue }
            let haystack = (URL(string: link.url)?.path ?? link.url) + " " + link.label
            let score = topics.filter { $0.matches(haystack) }.count
            if score > 0 { scored.append((link, score)) }
        }
        return scored.sorted { $0.score > $1.score }.map(\.link)
    }

    /// Host without `www.`, nil for an address that is not a web address.
    public static func siteHost(_ address: String) -> String? {
        guard let components = URLComponents(string: address), components.scheme?.lowercased().hasPrefix("http") == true,
              var host = components.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// An address without scheme, `www.`, fragment and trailing slash, for comparing.
    public static func normalized(_ address: String) -> String {
        var text = address.lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
