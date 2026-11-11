import Foundation

/// Opening hours a page states in machine-readable form (schema.org in a `application/ld+json` block):
/// `openingHoursSpecification` entries and `openingHours` strings such as `Mo-Fr 10:00-18:00`.
/// No guessing involved, so this is tried before the free text of the page is read.
public enum ParkStructuredHours {
    private struct Entry {
        var days: Set<String>
        var open: String
        var close: String
    }

    /// The `<script type="application/ld+json">` blocks of a page, as written.
    public static func jsonLDBlocks(inHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<script[^>]*application/ld\\+json[^>]*>(.*?)</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }.filter { !$0.isEmpty }.prefix(10).map { $0 }
    }

    /// Rules and one readable line per rule. Empty when the blocks hold no opening hours.
    public static func rules(in blocks: [String]) -> (rules: [ParkOpeningRule], lines: [String]) {
        var entries: [Entry] = []
        for block in blocks {
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            collect(json, into: &entries, depth: 0)
        }
        // One rule per time range, with every day that has it.
        var rules: [ParkOpeningRule] = []
        var order: [[String]] = []
        var daysByRange: [String: Set<String>] = [:]
        for entry in entries {
            let key = entry.open + "-" + entry.close
            if daysByRange[key] == nil { order.append([entry.open, entry.close]) }
            daysByRange[key, default: []].formUnion(entry.days)
        }
        var lines: [String] = []
        for range in order {
            let (open, close) = (range[0], range[1])
            let days = daysByRange[open + "-" + close] ?? []
            rules.append(ParkOpeningRule(days: ParkDaySelection.tokens(from: days), open: open, close: close))
            let names = ParkDaySelection.weekdayTokens.filter { days.contains($0) }.map { $0.capitalized }.joined(separator: ", ")
            lines.append("\(names) \(open)-\(close)")
        }
        return (rules, lines)
    }

    private static func collect(_ node: Any, into entries: inout [Entry], depth: Int) {
        guard depth < 8 else { return }
        if let list = node as? [Any] {
            for item in list { collect(item, into: &entries, depth: depth + 1) }
        } else if let object = node as? [String: Any] {
            if let specs = object["openingHoursSpecification"] {
                for spec in (specs as? [Any]) ?? [specs] { addSpecification(spec, into: &entries) }
            }
            if let hours = object["openingHours"] {
                for text in (hours as? [String]) ?? [hours as? String].compactMap({ $0 }) { addString(text, into: &entries) }
            }
            for (key, value) in object where key != "openingHoursSpecification" && key != "openingHours" {
                collect(value, into: &entries, depth: depth + 1)
            }
        }
    }

    /// A specification for a period or one date (`validFrom`, `validThrough`) is a special case, not the usual hours.
    private static func addSpecification(_ spec: Any, into entries: inout [Entry]) {
        guard let object = spec as? [String: Any], object["validFrom"] == nil, object["validThrough"] == nil,
              let open = clock(object["opens"] as? String), let close = clock(object["closes"] as? String), open != close
        else { return }
        let names = (object["dayOfWeek"] as? [String]) ?? [object["dayOfWeek"] as? String].compactMap { $0 }
        let days = Set(names.compactMap { day($0) })
        guard !days.isEmpty else { return }
        entries.append(Entry(days: days, open: open, close: close))
    }

    /// `Mo-Fr 10:00-18:00`, `Sa,Su 09:00-17:00`, `Mo-Fr 10:00-12:00,13:00-17:00`.
    private static func addString(_ text: String, into entries: inout [Entry]) {
        guard let firstDigit = text.firstIndex(where: \.isNumber) else { return }
        let dayPart = text[..<firstDigit]
        var days = Set<String>()
        if dayPart.trimmingCharacters(in: .whitespaces).isEmpty {
            days = Set(ParkDaySelection.weekdayTokens)
        } else {
            for piece in dayPart.split(whereSeparator: { $0 == "," || $0 == " " }) {
                let ends = piece.split(separator: "-").compactMap { day(String($0)) }
                guard let start = ends.first.flatMap({ ParkDaySelection.weekdayTokens.firstIndex(of: $0) }) else { continue }
                if ends.count == 2, let end = ParkDaySelection.weekdayTokens.firstIndex(of: ends[1]) {
                    var index = start
                    days.insert(ParkDaySelection.weekdayTokens[index])
                    while index != end {
                        index = (index + 1) % 7
                        days.insert(ParkDaySelection.weekdayTokens[index])
                    }
                } else {
                    days.insert(ParkDaySelection.weekdayTokens[start])
                }
            }
        }
        guard !days.isEmpty, let regex = try? NSRegularExpression(pattern: "(\\d{1,2}:\\d{2})\\s*-\\s*(\\d{1,2}:\\d{2})") else { return }
        let rest = String(text[firstDigit...])
        for match in regex.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)) {
            guard let a = Range(match.range(at: 1), in: rest), let b = Range(match.range(at: 2), in: rest),
                  let open = clock(String(rest[a])), let close = clock(String(rest[b])), open != close else { continue }
            entries.append(Entry(days: days, open: open, close: close))
        }
    }

    /// `monday`, `https://schema.org/Monday`, `Mo`, `Mon` as a day token (`mon`…).
    private static func day(_ text: String) -> String? {
        let name = (text.split(separator: "/").last.map(String.init) ?? text).lowercased()
        let prefixes = ["mo": 0, "tu": 1, "we": 2, "th": 3, "fr": 4, "sa": 5, "su": 6]
        guard name.count >= 2, let index = prefixes[String(name.prefix(2))] else { return nil }
        return ParkDaySelection.weekdayTokens[index]
    }

    /// `10:00`, `9:00`, `10:00:00` as `HH:mm`; nil for anything else.
    static func clock(_ text: String?) -> String? {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0...24).contains(hour), (0...59).contains(minute),
              hour < 24 || minute == 0 else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
}
