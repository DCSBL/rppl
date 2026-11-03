import Foundation

/// An announced event or closure read from a page: the exception for the park file and the line it came from.
public struct ParkEventFinding: Equatable, Sendable {
    public var exception: ParkOpeningException
    /// The source line, as written.
    public var line: String
    public var sourceURL: String?
}

/// Reads dated announcements (events, closures) by plain code, so the dates are exactly those on the page.
/// Only on pages and under headings about events or news, only dates that are not past, at most `maxEvents`.
public enum ParkEventReader {
    public static let maxEvents = 12

    /// `today` is `yyyy-MM-dd` in the park's time zone. A date without a year counts for this year only.
    public static func read(_ pages: [ParkSourcePage], today: String) -> [ParkEventFinding] {
        var found: [ParkEventFinding] = []
        for page in pages {
            let pageIsAboutEvents = ParkImportTopic.events.matches(page.url) || ParkImportTopic.events.matches(page.title)
            for block in page.blocks where pageIsAboutEvents || ParkImportTopic.events.matches(block.heading) {
                let lines = block.text.split(separator: "\n").map(String.init)
                for (index, line) in lines.enumerated() {
                    guard let range = dateRange(in: line, today: today), range.end >= today else { continue }
                    let previous = index > 0 && dateRange(in: lines[index - 1], today: today) == nil ? lines[index - 1] : nil
                    guard let label = eventName(line: line, matched: range.matched, fallback: previous ?? block.heading) else { continue }
                    let closed = ["gesloten", "closed", "geschlossen"].contains { (label + " " + line).lowercased().contains($0) }
                    let exception = ParkOpeningException(
                        kind: closed ? ParkExceptionKind.closed : ParkExceptionKind.event, label: label,
                        from: range.start == range.end ? nil : range.start, until: range.start == range.end ? nil : range.end,
                        dates: range.start == range.end ? [range.start] : nil
                    )
                    let sourceURL = ParkImportCrawler.siteHost(page.url) != nil ? page.url : nil
                    let finding = ParkEventFinding(exception: exception, line: line, sourceURL: sourceURL)
                    if !found.contains(where: { sameEvent($0.exception, exception) }) { found.append(finding) }
                }
            }
        }
        found.sort { start($0.exception) < start($1.exception) }
        return Array(found.prefix(maxEvents))
    }

    /// The first day of an exception, for ordering.
    public static func start(_ exception: ParkOpeningException) -> String {
        exception.dates?.first ?? exception.from ?? exception.until ?? ""
    }

    public static func sameEvent(_ lhs: ParkOpeningException, _ rhs: ParkOpeningException) -> Bool {
        start(lhs) == start(rhs) && lhs.until == rhs.until
            && (lhs.label ?? "").caseInsensitiveCompare(rhs.label ?? "") == .orderedSame
    }

    /// One line as the person reads it: the date, then the name.
    public static func summary(of exception: ParkOpeningException) -> String {
        let date: String
        if let first = exception.dates?.first {
            date = first
        } else {
            date = [exception.from, exception.until].compactMap { $0 }.joined(separator: " - ")
        }
        return [exception.label, date].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Dates

    struct DateRange: Equatable {
        var start: String
        var end: String
        var matched: Range<String.Index>
    }

    private static let monthWords: [String: Int] = {
        var result = ParkOpeningReader.monthNamesLookup
        for (key, value) in ParkOpeningReader.monthAbbreviations { result[key] = value }
        return result
    }()

    private static let monthAlternatives = monthWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    /// `10 oktober 2026`, `10 t/m 12 oktober`, `10-10-2026`, `2026-10-10`, `October 10, 2026`.
    private static let dayFirst = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\.?(?:\s*(?:-|–|—|t/m|tot|bis|to)\s*(\d{1,2})\.?)?\s*(\#(monthAlternatives))\b\.?(?:,?\s*(\d{4}))?"#,
        options: [.caseInsensitive]
    )
    private static let monthFirst = try! NSRegularExpression(
        pattern: #"\b(\#(monthAlternatives))\.?\s+(\d{1,2})(?:st|n[d]|rd|th)?(?:\s*(?:-|–|—|to)\s*(\d{1,2})(?:st|n[d]|rd|th)?)?(?:,?\s*(\d{4}))?(?!\d)"#,
        options: [.caseInsensitive]
    )
    private static let numeric = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[-./](\d{1,2})[-./](\d{4})(?!\d)"#)
    private static let iso = try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#)

    static func dateRange(in line: String, today: String) -> DateRange? {
        let nsRange = NSRange(line.startIndex..., in: line)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return nil }
            return String(line[swiftRange])
        }
        func build(_ day: String?, _ endDay: String?, _ month: String?, _ year: String?, _ match: NSTextCheckingResult) -> DateRange? {
            guard let day = day.flatMap({ Int($0) }), let month = month.flatMap({ monthWords[$0.lowercased()] }),
                  let matched = Range(match.range, in: line) else { return nil }
            let todayYear = Int(today.prefix(4)) ?? 0
            let resolved = year.flatMap { Int($0) } ?? todayYear
            let end = endDay.flatMap { Int($0) } ?? day
            guard let start = text(resolved, month, day), let last = text(resolved, month, end), start <= last else { return nil }
            return DateRange(start: start, end: last, matched: matched)
        }
        if let match = iso.firstMatch(in: line, range: nsRange), let year = group(match, 1).flatMap({ Int($0) }),
           let month = group(match, 2).flatMap({ Int($0) }), let day = group(match, 3).flatMap({ Int($0) }),
           let matched = Range(match.range, in: line), let value = text(year, month, day) {
            return DateRange(start: value, end: value, matched: matched)
        }
        if let match = numeric.firstMatch(in: line, range: nsRange), let day = group(match, 1).flatMap({ Int($0) }),
           let month = group(match, 2).flatMap({ Int($0) }), let year = group(match, 3).flatMap({ Int($0) }),
           let matched = Range(match.range, in: line), let value = text(year, month, day) {
            return DateRange(start: value, end: value, matched: matched)
        }
        if let match = dayFirst.firstMatch(in: line, range: nsRange),
           let range = build(group(match, 1), group(match, 2), group(match, 3), group(match, 4), match) {
            return yearless(match, group(match, 4)) ? (range.start >= today ? range : nil) : range
        }
        if let match = monthFirst.firstMatch(in: line, range: nsRange),
           let range = build(group(match, 2), group(match, 3), group(match, 1), group(match, 4), match) {
            return yearless(match, group(match, 4)) ? (range.start >= today ? range : nil) : range
        }
        return nil
    }

    private static func yearless(_ match: NSTextCheckingResult, _ year: String?) -> Bool { year == nil }

    /// `yyyy-MM-dd` for a real calendar date, nil for 31 February.
    private static func text(_ year: Int, _ month: Int, _ day: Int) -> String? {
        guard (1...12).contains(month), day >= 1 else { return nil }
        let days = [31, year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= days[month - 1] else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: Names

    /// The line without its date and the separators around it; the previous line or heading when nothing is left.
    private static func eventName(line: String, matched: Range<String.Index>, fallback: String) -> String? {
        var rest = line
        rest.removeSubrange(matched)
        let candidate = clean(rest)
        let chosen = candidate.count >= 3 ? candidate : clean(fallback)
        guard chosen.count >= 3, chosen.count <= 120 else { return nil }
        return chosen.count > 60 ? String(chosen.prefix(60)).trimmingCharacters(in: .whitespaces) : chosen
    }

    private static func clean(_ text: String) -> String {
        let separators = CharacterSet(charactersIn: ":-–—|·,.;()[] \t")
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: separators)
        // A weekday in front of the date ("Sa 16. Januar") is not part of the name.
        let first = result.split(whereSeparator: { separators.contains($0.unicodeScalars.first!) }).first.map { $0.lowercased() } ?? ""
        if ParkOpeningReader.dayNames[first] != nil || ParkOpeningReader.dayAbbreviations[first] != nil {
            result = String(result.dropFirst(first.count)).trimmingCharacters(in: separators)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
