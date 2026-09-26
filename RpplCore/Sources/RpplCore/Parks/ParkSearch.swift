import Foundation

/// Free-text park search over name/address/place, fuzzy and typo-tolerant, order-independent.
///
/// Each query word must fuzzy-match some word in the park's searchable text; words can match
/// in any order, so `"nieuwegein down"` finds `"Down Under" · "... Nieuwegein"`.
public enum ParkSearch {
    /// Parks whose name or address match every word of `query` (fuzzily, in any order).
    /// Empty/blank query returns `parks` unchanged.
    public static func filter(_ parks: [Park], query: String) -> [Park] {
        let queryWords = words(in: query)
        guard !queryWords.isEmpty else { return parks }
        return parks.filter { matches($0, queryWords: queryWords) }
    }

    private struct RankedHit {
        let offset: Int
        let park: Park
        let score: Int
    }

    /// Matching parks, most-likely-hit first. Ties keep `parks`' incoming order.
    public static func rank(_ parks: [Park], query: String) -> [Park] {
        let queryWords = words(in: query)
        guard !queryWords.isEmpty else { return parks }
        return parks
            .enumerated()
            .compactMap { offset, park -> RankedHit? in
                guard matches(park, queryWords: queryWords) else { return nil }
                return RankedHit(offset: offset, park: park, score: score(park, queryWords: queryWords, query: query))
            }
            .sorted { a, b in
                a.score != b.score ? a.score > b.score : a.offset < b.offset
            }
            .map(\.park)
    }

    /// Higher is a better hit: exact/prefix whole-name matches beat per-word matches;
    /// name matches beat address matches; exact word matches beat prefix/fuzzy ones.
    private static func score(_ park: Park, queryWords: [String], query: String) -> Int {
        let foldedName = fold(park.name)
        let foldedQuery = fold(query)
        if foldedName == foldedQuery { return 1000 }
        if foldedName.hasPrefix(foldedQuery) { return 900 }
        if foldedName.contains(foldedQuery) { return 800 }

        let nameWords = words(in: park.name)
        let addressWords = words(in: park.address ?? "")
        return queryWords.reduce(0) { total, queryWord in
            if nameWords.contains(queryWord) { return total + 30 }
            if nameWords.contains(where: { $0.hasPrefix(queryWord) }) { return total + 20 }
            if addressWords.contains(queryWord) { return total + 8 }
            if addressWords.contains(where: { $0.hasPrefix(queryWord) }) { return total + 5 }
            return total + 1
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static func matches(_ park: Park, queryWords: [String]) -> Bool {
        let parkWords = words(in: park.name) + words(in: park.address ?? "")
        guard !parkWords.isEmpty else { return false }
        return queryWords.allSatisfy { queryWord in
            parkWords.contains { parkWord in wordsMatch(queryWord, parkWord) }
        }
    }

    private static func wordsMatch(_ queryWord: String, _ parkWord: String) -> Bool {
        // One-way prefix only: a short park word ("Nieuw") must not swallow a longer query ("nieuwegien").
        if parkWord.hasPrefix(queryWord) { return true }
        let tolerance = editTolerance(for: queryWord.count)
        guard tolerance > 0 else { return false }
        return levenshtein(queryWord, parkWord, threshold: tolerance) <= tolerance
    }

    /// Short words need an exact prefix match; longer words tolerate a typo or two.
    private static func editTolerance(for length: Int) -> Int {
        switch length {
        case 0...3: 0
        case 4...6: 1
        default: 2
        }
    }

    /// Lowercased, diacritic-folded words, punctuation stripped.
    private static func words(in text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Bounded edit distance; returns `threshold + 1` once exceeded (exact value beyond that is unused).
    private static func levenshtein(_ a: String, _ b: String, threshold: Int) -> Int {
        if abs(a.count - b.count) > threshold { return threshold + 1 }
        let a = Array(a)
        let b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}
