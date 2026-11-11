import Foundation

/// Reads a site's sitemap, so the import can see every page of the site and pick the ones that hold
/// opening hours, prices or contact details without having to find a link to them first.
public enum ParkSitemap {
    /// Pages kept from one site; a big shop or blog would only add noise.
    public static let maxPages = 500
    /// Sitemaps followed when the first one is an index.
    public static let maxChildren = 3

    /// The addresses in a sitemap file: `pages` for a page list, `sitemaps` for an index of other sitemaps.
    public static func locations(in xml: String) -> (pages: [String], sitemaps: [String]) {
        guard let regex = try? NSRegularExpression(pattern: "<loc>\\s*(.*?)\\s*</loc>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return ([], [])
        }
        let range = NSRange(xml.startIndex..., in: xml)
        let found = regex.matches(in: xml, range: range).compactMap { match -> String? in
            Range(match.range(at: 1), in: xml).map { decoded(String(xml[$0])) }
        }.filter { !$0.isEmpty }
        if xml.range(of: "<sitemapindex", options: .caseInsensitive) != nil {
            return ([], Array(found.prefix(maxChildren)))
        }
        return (Array(found.prefix(maxPages)), [])
    }

    /// The `Sitemap:` lines of a robots.txt.
    public static func sitemaps(inRobots text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].lowercased() == "sitemap" else { return nil }
            return parts[1]
        }
    }

    /// Where to look first: the usual address of the site's sitemap.
    public static func usualAddress(forSite address: String) -> String? {
        guard let components = URLComponents(string: address), let scheme = components.scheme, let host = components.host else { return nil }
        return "\(scheme)://\(host)/sitemap.xml"
    }

    /// Pages as links, so the crawler can score them like the links of a page (the address carries the topic).
    public static func links(_ addresses: [String]) -> [ParkSourceLink] {
        addresses.map { ParkSourceLink(url: $0, label: "") }
    }

    private static func decoded(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<![CDATA["), value.hasSuffix("]]>") { value = String(value.dropFirst(9).dropLast(3)) }
        return value.replacingOccurrences(of: "&amp;", with: "&")
    }
}
