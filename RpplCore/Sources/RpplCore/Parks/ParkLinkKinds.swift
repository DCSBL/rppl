import Foundation

/// The link types the editor offers. `ParkLink.kind` stays an opaque string: these are only the
/// keys the editor suggests, any other text is a custom link name and round-trips untouched.
public enum ParkLinkKinds {
    /// `booking` makes the park detail show a "Book online" button.
    public static let booking = "booking"
    public static let instagram = "instagram"
    public static let facebook = "facebook"
    public static let youtube = "youtube"
    public static let tiktok = "tiktok"
    public static let contact = "contact"
    public static let openingHours = "opening hours"
    public static let webcam = "webcam"

    /// In the order the editor lists them.
    public static let presets = [booking, instagram, facebook, youtube, tiktok, contact, openingHours, webcam]

    /// Case, outer spaces and repeated spaces do not make a different link.
    public static func normalizedKey(_ kind: String) -> String {
        kind.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    public static func isPreset(_ kind: String) -> Bool {
        presets.contains(normalizedKey(kind))
    }

    /// A guess from the address: instagram.com → `instagram`. nil for an address we do not know.
    public static func detect(url: String) -> String? {
        guard let host = URLComponents(string: url.contains("://") ? url : "https://" + url)?.host?.lowercased() else {
            return nil
        }
        func matches(_ domains: [String]) -> Bool {
            domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if matches(["instagram.com", "instagr.am"]) { return instagram }
        if matches(["facebook.com", "fb.com", "fb.me", "fb.watch"]) { return facebook }
        if matches(["youtube.com", "youtu.be"]) { return youtube }
        if matches(["tiktok.com"]) { return tiktok }
        return nil
    }

    /// Adds `link`, or replaces the url of the link with the same kind: one link per kind. A custom
    /// name that matches an existing one (any casing) overwrites it instead of adding a second.
    public static func upsert(_ link: ParkLink, into links: inout [ParkLink]) {
        let key = normalizedKey(link.kind)
        if let index = links.firstIndex(where: { normalizedKey($0.kind) == key }) {
            links[index] = link
        } else {
            links.append(link)
        }
    }

    /// Kinds that appear more than once, for a "same link twice" hint. Keys are normalized.
    public static func duplicateKinds(in links: [ParkLink]) -> Set<String> {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for link in links {
            let key = normalizedKey(link.kind)
            if key.isEmpty { continue }
            if !seen.insert(key).inserted { duplicates.insert(key) }
        }
        return duplicates
    }
}
