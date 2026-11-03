import Foundation

/// One park as the system search (Spotlight) shows it. Plain data, so what is indexed and how a park is
/// found is tested in Core; the app turns each entry into a Core Spotlight item.
public struct ParkSpotlightEntry: Equatable, Sendable {
    /// The park's link (`rppl://park/<id>`): what Spotlight hands back when the rider taps the result.
    public var identifier: String
    /// Result title: the full park name.
    public var title: String
    /// Line under the title: town and country (`Park.placeSubtitle`); nil when neither is known.
    public var subtitle: String?
    /// Extra words that find the park: the short name when it differs, then `ParkSpotlight.genericKeywords`.
    public var keywords: [String]
    public var latitude: Double
    public var longitude: Double
}

/// Parks in the system search: what gets indexed, and how a tapped result maps back to a park.
public enum ParkSpotlight {
    /// Name of the app's own Core Spotlight index, and the domain of every park item in it.
    public static let domain = "nl.dcsbl.rppl.parks"

    /// Bump when the entry layout changes, so an index built by an older app is rebuilt.
    public static let layoutVersion = 1

    /// Words every park answers to, so a search for "wakeboard" or "kabelpark" lists the parks too.
    public static let genericKeywords = ["cable park", "kabelpark", "wakeboard", "waterski"]

    /// Listed parks, ordered by identifier so the same parks always give the same entries.
    /// Permanently closed parks are left out, like in the list and map. `locale` sets the country name in the subtitle.
    public static func entries(for parks: [Park], locale: Locale = .current) -> [ParkSpotlightEntry] {
        parks
            .filter(\.isListed)
            .compactMap { entry(for: $0, locale: locale) }
            .sorted { $0.identifier < $1.identifier }
    }

    /// The park a tapped result stands for. nil for anything that is not a park link.
    public static func parkID(fromIdentifier identifier: String) -> String? {
        URL(string: identifier).flatMap(ParkDeepLink.parkID(from:))
    }

    /// Short text that changes whenever any entry (or `layoutVersion`) changes. The app keeps it as the
    /// index's client state, so a launch with the same parks does not index again. Fits the 250 bytes Core Spotlight allows.
    public static func fingerprint(of entries: [ParkSpotlightEntry]) -> String {
        let fieldSeparator = "\u{1F}"
        var text = "layout \(layoutVersion)"
        for entry in entries {
            let fields = [
                entry.identifier,
                entry.title,
                entry.subtitle ?? "",
                entry.keywords.joined(separator: fieldSeparator),
                String(entry.latitude),
                String(entry.longitude),
            ]
            text += "\n" + fields.joined(separator: "\u{1E}")
        }
        return ParkDataHash.sha256Hex(Data(text.utf8))
    }

    private static func entry(for park: Park, locale: Locale) -> ParkSpotlightEntry? {
        let title = park.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !park.id.isEmpty, let link = ParkDeepLink.url(forParkID: park.id) else { return nil }
        return ParkSpotlightEntry(
            identifier: link.absoluteString,
            title: title,
            subtitle: park.placeSubtitle(locale: locale),
            keywords: keywords(for: park, title: title),
            latitude: park.location.lat,
            longitude: park.location.lon
        )
    }

    private static func keywords(for park: Park, title: String) -> [String] {
        var words: [String] = []
        let short = park.compactName.trimmingCharacters(in: .whitespacesAndNewlines)
        if short.caseInsensitiveCompare(title) != .orderedSame { words.append(short) }
        return words + genericKeywords
    }
}
