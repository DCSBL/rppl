import Foundation

/// A page the import wants to read next, and why.
public struct ParkImportTarget: Equatable, Sendable {
    public var url: String
    public var topic: ParkImportTopic
    /// `true` when the page is not linked anywhere that was read: a usual address of the site (`/prijzen`).
    public var isGuess: Bool

    public init(url: String, topic: ParkImportTopic, isGuess: Bool) {
        self.url = url
        self.topic = topic
        self.isGuess = isGuess
    }
}

/// The part of the import that decides where to look next. Pure, so the loop around it (fetching and
/// asking the model) stays small. It only ever names pages of the site the person started from.
public enum ParkImportAgent {
    /// Pages read in one import, the first one included.
    public static let maxPages = 8
    /// Addresses tried without a link to them. A miss costs a request, so the number is small.
    public static let maxGuesses = 3

    private static let wellKnownPaths: [ParkImportTopic: [String]] = [
        .opening: ["/openingstijden", "/openingstijden/", "/opening-hours", "/oeffnungszeiten", "/hours"],
        .prices: ["/prijzen", "/tarieven", "/preise", "/prices"],
        .contact: ["/contact", "/kontakt"],
        .events: ["/agenda", "/evenementen", "/events", "/veranstaltungen"],
    ]

    /// Where a rescan of an existing park starts: the page its opening hours were read from, the pages an
    /// earlier import used, then the website. Web addresses only, each once, at most `maxPages`.
    public static func startAddresses(for park: Park) -> [String] {
        var seen = Set<String>()
        let all = [park.opening?.sourceURL] + (park.sources ?? []).map { Optional($0) } + [park.website]
        return all.compactMap { $0.flatMap(ParkText.normalizedWebAddress) }
            .filter { seen.insert(ParkImportCrawler.normalized($0)).inserted }
            .prefix(maxPages).map { $0 }
    }

    /// Adds `addresses` to the park's remembered sources (the editor tidies the list when it saves).
    public static func remember(_ addresses: [String], in park: Park) -> Park {
        var park = park
        var sources = park.sources ?? []
        for address in addresses where !sources.contains(where: { ParkImportCrawler.normalized($0) == ParkImportCrawler.normalized(address) }) {
            sources.append(address)
        }
        park.sources = sources.isEmpty ? nil : sources
        return park
    }

    /// What the park and the findings still lack, most useful first. A rescan (`refreshing`) asks for
    /// everything the page can hold, because what the park has may be out of date.
    public static func missingTopics(
        candidates: ParkImportCandidates, park: Park, refreshing: Bool = false
    ) -> [ParkImportTopic] {
        var missing: [ParkImportTopic] = []
        if candidates.opening == nil, refreshing || park.opening?.hasSchedule != true { missing.append(.opening) }
        if candidates.prices.isEmpty, refreshing || (park.prices ?? []).isEmpty { missing.append(.prices) }
        if candidates.address == nil, refreshing || (park.address ?? "").isEmpty { missing.append(.contact) }
        if candidates.events.isEmpty { missing.append(.events) }
        return missing
    }

    /// The next page to read for the first missing topic that has one: a link on a page read so far, else
    /// a page of the site's `sitemap`, else a usual address (up to `maxGuesses`). nil when there is nothing
    /// left to try.
    public static func next(
        pages: [ParkSourcePage], missing: [ParkImportTopic], visited: Set<String>, guessesUsed: Int,
        sitemap: [ParkSourceLink] = []
    ) -> ParkImportTarget? {
        guard pages.count < maxPages else { return nil }
        // The sitemap is searched like one more page, after the pages that were read.
        let searched = sitemap.isEmpty || pages.isEmpty ? pages : pages + [ParkSourcePage(url: pages[0].url, links: sitemap)]
        for topic in missing {
            for page in searched {
                if let link = ParkImportCrawler.candidates(from: page, topics: [topic], visited: visited).first {
                    return ParkImportTarget(url: link.url, topic: topic, isGuess: false)
                }
            }
        }
        guard guessesUsed < maxGuesses, let first = pages.first(where: { ParkImportCrawler.siteHost($0.url) != nil }),
              let components = URLComponents(string: first.url), let scheme = components.scheme,
              let host = components.host else { return nil }
        let seen = Set(visited.map(ParkImportCrawler.normalized))
        for topic in missing {
            for path in wellKnownPaths[topic] ?? [] {
                let address = "\(scheme)://\(host)\(path)"
                if !seen.contains(ParkImportCrawler.normalized(address)) {
                    return ParkImportTarget(url: address, topic: topic, isGuess: true)
                }
            }
        }
        return nil
    }
}
