import Foundation

/// Picks one language variant of short park text ("per 2 uur" / "pour 2 heures" / "per 2 hours").
/// Long prose (description, cable description, opening note) is written once in the park's main
/// language and does not go through here.
public enum ParkLanguage {
    /// The language part of a BCP-47 tag, lowercased: `fr-BE` and `fr_BE` both give `fr`.
    public static func base(_ tag: String) -> String {
        let lower = tag.lowercased()
        let end = lower.firstIndex(where: { $0 == "-" || $0 == "_" }) ?? lower.endIndex
        return String(lower[..<end])
    }

    /// Variant for the reader, in this order: a reader language (exact tag, then same language
    /// code), the park's languages in order (main first), English, then `fallback`
    /// (the plain-string form, or any one variant when that is nil).
    public static func resolve(
        _ variants: [String: String]?,
        fallback: String?,
        readerLanguages: [String],
        parkLanguages: [String]?
    ) -> String? {
        guard let variants, !variants.isEmpty else { return fallback }
        func match(_ tag: String) -> String? {
            if let exact = variants.first(where: { $0.key.caseInsensitiveCompare(tag) == .orderedSame }) {
                return exact.value
            }
            let code = base(tag)
            return variants.sorted { $0.key < $1.key }.first { base($0.key) == code }?.value
        }
        for tag in readerLanguages + (parkLanguages ?? []) + ["en"] {
            if let value = match(tag) { return value }
        }
        return fallback ?? variants.sorted { $0.key < $1.key }.first?.value
    }

    /// The reader's preferred languages, best first.
    public static var readerLanguages: [String] { Locale.preferredLanguages }

    /// Variant keys must be language tags (`nl`, `fr-BE`); anything else is not a language.
    public static func isValidTag(_ tag: String) -> Bool {
        tag.range(of: "^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil
    }
}

/// Reads a field written either as plain text (`per: per hour`) or as a map from language tag to
/// text (`per: { nl: per uur, en: per hour }`).
enum LocalizedField {
    /// `text` is the plain string, or for a map the English variant, else the first by tag.
    static func decode<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>, forKey key: K
    ) throws -> (text: String?, variants: [String: String]?) {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return (text, nil) }
        guard let map = try container.decodeIfPresent([String: String].self, forKey: key), !map.isEmpty else {
            return (nil, nil)
        }
        let text = map["en"] ?? map.sorted { $0.key < $1.key }.first?.value
        return (text, map)
    }

    static func encode<K: CodingKey>(
        _ container: inout KeyedEncodingContainer<K>, text: String?, variants: [String: String]?, forKey key: K
    ) throws {
        if let variants, !variants.isEmpty {
            try container.encode(variants, forKey: key)
        } else {
            try container.encodeIfPresent(text, forKey: key)
        }
    }
}
