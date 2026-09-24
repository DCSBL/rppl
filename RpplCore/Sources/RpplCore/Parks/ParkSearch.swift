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

    private static func matches(_ park: Park, queryWords: [String]) -> Bool {
        let parkWords = words(in: park.name) + words(in: park.address ?? "")
        guard !parkWords.isEmpty else { return false }
        return queryWords.allSatisfy { queryWord in
            parkWords.contains { parkWord in wordsMatch(queryWord, parkWord) }
        }
    }

    private static func wordsMatch(_ queryWord: String, _ parkWord: String) -> Bool {
        if parkWord.hasPrefix(queryWord) || queryWord.hasPrefix(parkWord) { return true }
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
