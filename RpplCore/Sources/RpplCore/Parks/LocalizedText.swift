import Foundation

/// Short park text that may come in several languages ("per 2 uur" / "pour 2 heures" / "per 2 hours").
/// YAML writes either plain text (`per: per hour`) or a map from language tag to text
/// (`per: { nl: per uur, en: per hour }`). Long prose (description, cable description, opening
/// note) is written once in the park's main language and is not a `LocalizedText`.
public struct LocalizedText: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    /// The plain text. For a map: the English variant, else the first by tag.
    public var text: String
    /// Variant per language tag (`nl`, `fr-BE`); empty for plain text.
    public var variants: [String: String]

    public init(_ text: String, variants: [String: String] = [:]) {
        self.text = text
        self.variants = variants
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            self.init(plain)
        } else {
            let map = try container.decode([String: String].self)
            self.init(map["en"] ?? map.min { $0.key < $1.key }?.value ?? "", variants: map)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if variants.isEmpty { try container.encode(text) } else { try container.encode(variants) }
    }

    /// The variant for the reader: first a reader language, then the park's languages (main
    /// first), then English, matched on language code (`fr-BE` reads the `fr` variant). Falls
    /// back to `text`.
    public func resolved(
        parkLanguages: [String]?, readerLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        for tag in readerLanguages + (parkLanguages ?? []) + ["en"] {
            let code = Self.languageCode(tag)
            if let match = variants.first(where: { Self.languageCode($0.key) == code }) { return match.value }
        }
        return text
    }

    /// `fr-BE` and `fr_BE` both give `fr`.
    static func languageCode(_ tag: String) -> String {
        tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
    }
}
