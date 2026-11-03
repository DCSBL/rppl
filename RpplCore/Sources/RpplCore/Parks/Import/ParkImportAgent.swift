import Foundation

/// A page the import wants to read next, and why.
public struct ParkImportTarget: Equatable, Sendable {
    public var url: String
    public var topic: ParkImportTopic
    /// `true` when the page is not linked anywhere that was read: a usual address of the site (`/prijzen`).
    public var isGuess: Bool
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
    ]

    /// What the park and the findings still lack, most useful first.
    public static func missingTopics(candidates: ParkImportCandidates, park: Park) -> [ParkImportTopic] {
        var missing: [ParkImportTopic] = []
        if park.opening?.hasSchedule != true, candidates.opening == nil { missing.append(.opening) }
        if candidates.prices.isEmpty, (park.prices ?? []).isEmpty { missing.append(.prices) }
        if candidates.address == nil, (park.address ?? "").isEmpty { missing.append(.contact) }
        return missing
    }

    /// The next page to read for the first missing topic that has one: a link on a page read so far, else
    /// a usual address (up to `maxGuesses`). nil when there is nothing left to try.
    public static func next(
        pages: [ParkSourcePage], missing: [ParkImportTopic], visited: Set<String>, guessesUsed: Int
    ) -> ParkImportTarget? {
        guard pages.count < maxPages else { return nil }
        for topic in missing {
            for page in pages {
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
