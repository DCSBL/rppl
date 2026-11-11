import Foundation

/// Opening hours read from a source by plain code: days, months and time ranges in Dutch, German and
/// English ("ma t/m vr 10:00 - 18:00", "April: Sa, So 12.30 bis 17.00 Uhr"). Every time in the result
/// is a time that stands in the source, so nothing here can be made up.
public struct ParkOpeningFinding: Equatable, Sendable {
    public var rules: [ParkOpeningRule]
    /// The source lines the rules were read from, in order.
    public var lines: [String]
    /// The page the hours were read from (a web address), when the source is a web page.
    public var sourceURL: String?
    /// Read by code, or by the model with every time found in the source text. `false` when the model gave
    /// a time that is not in the text: shown to the person, switched off by default.
    public var isVerified: Bool

    public init(rules: [ParkOpeningRule], lines: [String], sourceURL: String?, isVerified: Bool = true) {
        self.rules = rules
        self.lines = lines
        self.sourceURL = sourceURL
        self.isVerified = isVerified
    }
}

/// One line of opening hours as the model returned it: text, to be checked and turned into a rule by code.
public struct ParkModelHours: Equatable, Sendable {
    /// Days as written ("ma t/m vr"); empty is every day.
    public var days: String
    /// Months as written ("april - september"); empty is all year.
    public var months: String
    /// `HH:mm`, 24 hour.
    public var open: String
    public var close: String

    public init(days: String, months: String, open: String, close: String) {
        self.days = days
        self.months = months
        self.open = open
        self.close = close
    }
}

public enum ParkOpeningReader {
    // MARK: Reading

    /// The hours of all pages together; the first page that has any decides `sourceURL`.
    public static func read(_ pages: [ParkSourcePage]) -> ParkOpeningFinding? {
        var rules: [ParkOpeningRule] = []
        var lines: [String] = []
        var sourceURL: String?
        for page in pages {
            let (found, used) = read(page)
            guard !found.isEmpty else { continue }
            for rule in found where !rules.contains(where: { sameRule($0, rule) }) { rules.append(rule) }
            for line in used where !lines.contains(line) { lines.append(line) }
            if sourceURL == nil, ParkImportCrawler.siteHost(page.url) != nil { sourceURL = page.url }
        }
        return rules.isEmpty ? nil : ParkOpeningFinding(rules: rules, lines: lines, sourceURL: sourceURL)
    }

    /// The lines that talk about opening hours but gave no rule: shown as a note instead of nothing.
    public static func hoursText(_ pages: [ParkSourcePage]) -> String? {
        var found: [String] = []
        for page in pages {
            for block in page.blocks where ParkImportTopic.opening.matches(block.heading) || hasHoursWord(block.text) {
                for line in block.text.split(separator: "\n") where !timeRanges(in: String(line)).isEmpty {
                    let text = String(line)
                    if !found.contains(text) { found.append(text) }
                }
            }
        }
        return found.isEmpty ? nil : found.joined(separator: "\n")
    }

    /// The text about opening hours the model is asked to read when code found no rule: blocks that are about
    /// hours and have a number in them. nil when there is none.
    public static func modelHoursText(_ pages: [ParkSourcePage], maxCharacters: Int = ParkImportChunker.maxCharacters) -> String? {
        var parts: [String] = []
        for page in pages {
            for block in page.blocks where (ParkImportTopic.opening.matches(block.heading) || hasHoursWord(block.text))
                && block.text.contains(where: \.isNumber) {
                let text = block.heading.isEmpty ? block.text : block.heading + "\n" + block.text
                if !parts.contains(text) { parts.append(text) }
            }
        }
        let joined = parts.joined(separator: "\n\n")
        return joined.isEmpty ? nil : String(joined.prefix(maxCharacters))
    }

    /// Rules from what the model read. Days and months go through the same word lists as the parser, and a
    /// rule needs a valid time range. A time that does not stand in the pages' text makes the whole finding
    /// unverified. nil when nothing usable is left.
    public static func finding(from hours: [ParkModelHours], pages: [ParkSourcePage]) -> ParkOpeningFinding? {
        let source = pages.map(\.evidenceText).joined(separator: "\n")
        var rules: [ParkOpeningRule] = []
        var lines: [String] = []
        var verified = true
        for item in hours.prefix(ParkLimits.rules) {
            guard let open = ParkStructuredHours.clock(item.open), let close = ParkStructuredHours.clock(item.close), open != close,
                  let start = ParkClock.minutes(open), let end = ParkClock.minutes(close), end > start else { continue }
            let days = item.days.trimmingCharacters(in: .whitespaces).isEmpty ? nil : self.days(in: item.days)
            let months = ParkDaySelection.months(from: Set(self.months(in: item.months)))
            let rule = ParkOpeningRule(months: months, days: days, open: open, close: close)
            guard !rules.contains(where: { sameRule($0, rule) }) else { continue }
            rules.append(rule)
            lines.append(summary(of: [rule]))
            if !timeStandsInText(open, source) || !timeStandsInText(close, source) { verified = false }
        }
        guard !rules.isEmpty else { return nil }
        let url = pages.first { ParkImportCrawler.siteHost($0.url) != nil && modelHoursText([$0]) != nil }?.url
        return ParkOpeningFinding(rules: rules, lines: lines, sourceURL: url, isVerified: verified)
    }

    /// Whether `HH:mm` is written in `text` as `12:30`, `12.30`, `12h30` or, for a full hour, as `12`.
    static func timeStandsInText(_ time: String, _ text: String) -> Bool {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        let pattern = minute == 0 ? "(?<!\\d)0?\(hour)(?!\\d)" : "(?<!\\d)0?\(hour)\\D{0,2}\(String(format: "%02d", minute))(?!\\d)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func read(_ page: ParkSourcePage) -> (rules: [ParkOpeningRule], lines: [String]) {
        // What the page states in machine-readable form needs no reading of text.
        let structured = ParkStructuredHours.rules(in: page.structuredData)
        if !structured.rules.isEmpty { return structured }
        var rules: [ParkOpeningRule] = []
        var used: [String] = []
        let pageIsAboutHours = ParkImportTopic.opening.matches(page.url) || ParkImportTopic.opening.matches(page.title)
        for block in page.blocks {
            let trusted = pageIsAboutHours || ParkImportTopic.opening.matches(block.heading) || hasHoursWord(block.text)
            guard trusted else { continue }
            var context = months(in: block.heading)
            for line in block.text.split(separator: "\n").map(String.init) {
                let times = timeRanges(in: line)
                let lineMonths = months(in: line)
                if times.isEmpty {
                    if !lineMonths.isEmpty { context = lineMonths }
                    continue
                }
                let lowered = line.lowercased()
                if lowered.contains("€") || lowered.contains(" eur") { continue }
                let ruleDays = days(in: line)
                let ruleMonths = lineMonths.isEmpty ? context : lineMonths
                for time in times {
                    let rule = ParkOpeningRule(
                        months: ParkDaySelection.months(from: Set(ruleMonths)), days: ruleDays, open: time.open, close: time.close
                    )
                    if !rules.contains(where: { sameRule($0, rule) }) { rules.append(rule) }
                }
                used.append(line)
            }
        }
        return (rules, used)
    }

    private static func sameRule(_ lhs: ParkOpeningRule, _ rhs: ParkOpeningRule) -> Bool {
        lhs.months == rhs.months && lhs.days == rhs.days && lhs.open == rhs.open && lhs.close == rhs.close
    }

    static func hasHoursWord(_ text: String) -> Bool {
        ParkImportTopic.opening.matches(text)
    }

    /// One short line per rule, for the review list.
    public static func summary(of rules: [ParkOpeningRule]) -> String {
        rules.map { rule in
            var parts: [String] = []
            if let months = rule.months, !months.isEmpty { parts.append(months.map { monthNames[$0 - 1] }.joined(separator: ", ")) }
            if let days = rule.days, !days.isEmpty { parts.append(days.map { $0.capitalized }.joined(separator: ", ")) }
            parts.append("\(rule.open)–\(rule.close)")
            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    // MARK: Times

    /// `12:30 - 17:00`, `12.30 tot 17.00 uur`, `10 - 18 uur`, `10h-18h`. A range needs minutes or a word
    /// for hours ("uur", "Uhr", "h"), so a date like `10-12` or a price is not mistaken for a time.
    static func timeRanges(in line: String) -> [(open: String, close: String)] {
        var found: [(open: String, close: String)] = []
        let range = NSRange(line.startIndex..., in: line)
        for match in timePattern.matches(in: line, range: range) {
            func group(_ index: Int) -> String? {
                let nsRange = match.range(at: index)
                guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: line) else { return nil }
                return String(line[swiftRange])
            }
            guard let openHour = group(1).flatMap({ Int($0) }), let closeHour = group(3).flatMap({ Int($0) }) else { continue }
            let hasMinutes = group(2) != nil || group(4) != nil
            let hasHourWord = group(5) != nil
            guard hasMinutes || hasHourWord else { continue }
            let openMinute = group(2).flatMap { Int($0) } ?? 0
            let closeMinute = group(4).flatMap { Int($0) } ?? 0
            guard (0...23).contains(openHour), (0...24).contains(closeHour), (0...59).contains(openMinute),
                  (0...59).contains(closeMinute) else { continue }
            let open = ParkClock.text(minutes: openHour * 60 + openMinute)
            let close = ParkClock.text(minutes: closeHour * 60 + closeMinute)
            guard open != close else { continue }
            found.append((open, close))
        }
        return found
    }

    private static let timePattern = try! NSRegularExpression(
        pattern: #"(?<![\d.:,])(\d{1,2})(?:[:.h](\d{2}))?\s*(?:uur|u|h|uhr)?\s*(?:-|–|—|tot|bis|to|until|till)\s*(\d{1,2})(?:[:.h](\d{2}))?\s*(uur\b|uhr\b|h\b|u\b)?(?![\d])"#,
        options: [.caseInsensitive]
    )

    // MARK: Days and months

    private static let rangeWords: Set<String> = ["-", "tm", "tot", "bis", "to", "through", "thru", "until", "till"]
    private static let listWords: Set<String> = ["en", "und", "and", "of", "&"]

    static let dayNames: [String: Int] = [
        "maandag": 0, "dinsdag": 1, "woensdag": 2, "donderdag": 3, "vrijdag": 4, "zaterdag": 5, "zondag": 6,
        "monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3, "friday": 4, "saturday": 5, "sunday": 6,
        "montag": 0, "dienstag": 1, "mittwoch": 2, "donnerstag": 3, "freitag": 4, "samstag": 5, "sonntag": 6,
        "sonnabend": 5,
    ]
    static let dayAbbreviations: [String: Int] = [
        "ma": 0, "di": 1, "wo": 2, "do": 3, "vr": 4, "za": 5, "zo": 6,
        "mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6,
        "mo": 0, "mi": 2, "fr": 4, "sa": 5, "so": 6,
    ]
    static let monthNamesLookup: [String: Int] = [
        "januari": 1, "februari": 2, "maart": 3, "april": 4, "mei": 5, "juni": 6, "juli": 7, "augustus": 8,
        "september": 9, "oktober": 10, "november": 11, "december": 12,
        "january": 1, "february": 2, "march": 3, "june": 6, "july": 7, "august": 8, "october": 10,
        "januar": 1, "februar": 2, "märz": 3, "maerz": 3, "mai": 5, "dezember": 12,
    ]
    static let monthAbbreviations: [String: Int] = [
        "jan": 1, "feb": 2, "mrt": 3, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "sept": 9, "okt": 10, "oct": 10, "nov": 11, "dec": 12, "dez": 12,
    ]
    private static let weekendWords: Set<String> = ["weekend", "weekenden", "weekends", "wochenende"]
    private static let weekdayWords: Set<String> = [
        "weekdagen", "doordeweeks", "werkdagen", "weekdays", "wochentags", "werktags",
    ]

    static func tokens(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        let text = line.lowercased().replacingOccurrences(of: "t/m", with: "tm").replacingOccurrences(of: "t.m.", with: "tm")
        for char in text {
            if char.isLetter || char.isNumber {
                current.append(char)
            } else if char == "-" || char == "–" || char == "—" {
                flush()
                result.append("-")
            } else if char == "&" {
                flush()
                result.append("&")
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    /// The `days` selector for the days named in a line; nil when none are named (every day).
    static func days(in line: String) -> [String]? {
        let words = tokens(line)
        var days = Set<Int>()
        for word in words {
            if weekendWords.contains(word) { days.formUnion([5, 6]) }
            if weekdayWords.contains(word) { days.formUnion(0...4) }
        }
        days.formUnion(sequence(in: words, names: dayNames, abbreviations: dayAbbreviations, count: 7))
        return ParkDaySelection.tokens(from: Set(days.map { ParkDaySelection.weekdayTokens[$0] }))
    }

    /// The months named in a line, sorted. Empty when none are named.
    static func months(in line: String) -> [Int] {
        let found = sequence(in: tokens(line), names: monthNamesLookup, abbreviations: monthAbbreviations, count: 12, base: 1)
        return found.sorted()
    }

    /// Names and ranges ("ma t/m wo", "oktober - maart", "za en zo") in a list of words. Full names always
    /// count; an abbreviation only at the start of a line or next to another day or a range or list word,
    /// so "zo" in "zo open" or "do" in "do not" is left alone.
    private static func sequence(
        in words: [String], names: [String: Int], abbreviations: [String: Int], count: Int, base: Int = 0
    ) -> Set<Int> {
        func value(at index: Int) -> Int? {
            guard words.indices.contains(index) else { return nil }
            let word = words[index]
            if let full = names[word] { return full }
            guard let short = abbreviations[word] else { return nil }
            let neighbours = [index - 1, index + 1].filter { words.indices.contains($0) }.map { words[$0] }
            let attached = index == 0 || neighbours.contains {
                rangeWords.contains($0) || listWords.contains($0) || names[$0] != nil || abbreviations[$0] != nil
            }
            return attached ? short : nil
        }
        var result = Set<Int>()
        var index = 0
        while index < words.count {
            guard let start = value(at: index) else {
                index += 1
                continue
            }
            if index + 2 < words.count, rangeWords.contains(words[index + 1]), let end = value(at: index + 2) {
                var current = start - base
                let last = end - base
                result.insert(current + base)
                while current != last {
                    current = (current + 1) % count
                    result.insert(current + base)
                }
                index += 3
            } else {
                result.insert(start)
                index += 1
            }
        }
        return result
    }
}
