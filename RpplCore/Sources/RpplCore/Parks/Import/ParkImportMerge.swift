import Foundation

/// The park fields the import can propose. A closed list on purpose: opening hours, cables and the
/// location stay manual.
public enum ParkImportField: String, CaseIterable, Sendable {
    case phone, email, website, address, links, prices, facilities, opening, events
}

/// A price as the model read it, with the words it says it read it from.
public struct ParkImportPrice: Equatable, Sendable {
    public var price: ParkPrice
    public var quote: String?

    public init(price: ParkPrice, quote: String?) {
        self.price = price
        self.quote = quote
    }
}

/// Everything found so far, from code and from the model. Grows when the person adds another source.
public struct ParkImportCandidates: Equatable, Sendable {
    public var phone: String?
    public var email: String?
    public var website: String?
    public var address: String?
    public var links: [ParkLink] = []
    public var prices: [ParkImportPrice] = []
    public var facilities: [String] = []
    /// Opening hours read by code. Never from the model.
    public var opening: ParkOpeningFinding?
    /// Lines about opening hours that gave no rule, kept as a note.
    public var openingNote: String?
    /// Dated events and closures read by code. Never from the model.
    public var events: [ParkEventFinding] = []

    public init() {}

    /// The fields that have something in them, for showing what a page added.
    public var fields: Set<ParkImportField> {
        var result = Set<ParkImportField>()
        if phone != nil { result.insert(.phone) }
        if email != nil { result.insert(.email) }
        if website != nil { result.insert(.website) }
        if address != nil { result.insert(.address) }
        if !links.isEmpty { result.insert(.links) }
        if !prices.isEmpty { result.insert(.prices) }
        if !facilities.isEmpty { result.insert(.facilities) }
        if opening != nil || openingNote != nil { result.insert(.opening) }
        if !events.isEmpty { result.insert(.events) }
        return result
    }

    /// What plain code can read from a page: phone, email, social links and, for a web page, the site address.
    public init(page: ParkSourcePage) {
        phone = page.phones.first
        email = page.emails.first
        if let host = ParkImportCrawler.siteHost(page.url), ParkLinkKinds.detect(url: page.url) == nil,
           let scheme = URLComponents(string: page.url)?.scheme {
            website = "\(scheme)://\(host)"
        }
        for link in page.links {
            if let kind = ParkLinkKinds.detect(url: link.url) { ParkLinkKinds.upsert(ParkLink(kind: kind, url: link.url), into: &links) }
        }
    }

    /// Adds what `other` found; a value already here stays, a list adds only what is new.
    public mutating func merge(_ other: ParkImportCandidates) {
        phone = phone ?? other.phone
        email = email ?? other.email
        website = website ?? other.website
        address = address ?? other.address
        opening = opening ?? other.opening
        openingNote = openingNote ?? other.openingNote
        for event in other.events where !events.contains(where: { ParkEventReader.sameEvent($0.exception, event.exception) }) {
            events.append(event)
        }
        for link in other.links where !links.contains(where: { ParkLinkKinds.normalizedKey($0.kind) == ParkLinkKinds.normalizedKey(link.kind) }) {
            links.append(link)
        }
        for price in other.prices where !prices.contains(where: { Self.sameName($0.price.name, price.price.name) }) {
            prices.append(price)
        }
        for facility in other.facilities where !facilities.contains(where: { Self.sameName($0, facility) }) {
            facilities.append(facility)
        }
    }

    /// A price in the shape of the park file, from what the model returned as plain text. nil when there is
    /// no name or no readable amount.
    public static func price(
        name: String, amount: String, per: String, note: String, quote: String, currency: String
    ) -> ParkImportPrice? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, case .amount(let parsed) = ParkPriceParser.parse(amount) else { return nil }
        let option = ParkPriceOption(
            amount: parsed.text,
            currency: currency,
            per: unit(per),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let quote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParkImportPrice(price: ParkPrice(name: name, options: [option]), quote: quote.isEmpty ? nil : quote)
    }

    /// `hour`, `day`, `session` and `person` for the words that mean those; other text stays as written.
    static func unit(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.isEmpty { return nil }
        switch cleaned {
        case "hour", "uur", "stunde", "heure", "h": return ParkPriceUnit.hour
        case "day", "dag", "tag", "jour", "dagkaart": return ParkPriceUnit.day
        case "session", "sessie", "sitzung", "séance": return ParkPriceUnit.session
        case "person", "persoon", "person.", "pp", "p.p.", "personne": return ParkPriceUnit.person
        default: return cleaned.count <= 30 ? cleaned : nil
        }
    }

    /// The currency the source talks about: euro unless a sign or code says otherwise.
    public static func currency(in text: String, fallback: String? = nil) -> String {
        let upper = text.uppercased()
        if upper.contains("CHF") { return "CHF" }
        if upper.contains("£") || upper.contains("GBP") { return "GBP" }
        if upper.contains("€") || upper.contains("EUR") { return "EUR" }
        return fallback ?? "EUR"
    }

    public static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }
}

/// One proposed change to a park, for the person to accept or leave.
public struct ParkImportItem: Identifiable, Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case phone(String)
        case email(String)
        case website(String)
        case address(String)
        case link(ParkLink)
        case price(ParkPrice)
        case facility(String)
        /// The whole set of opening rules; a partial schedule would say something the source does not.
        case opening(rules: [ParkOpeningRule], sourceURL: String?)
        /// Hours the reader could not turn into rules, as the source words them.
        case openingNote(String)
        /// An announced event or closure, for `opening.exceptions`.
        case event(ParkOpeningException)
    }

    public var id: String
    public var field: ParkImportField
    public var value: Value
    /// How the park has it now, when this replaces something; nil for an addition.
    public var previous: String?
    public var level: ParkImportGrounding.Level
    /// What it was read from, when that helps the person judge it (the source lines of the opening hours).
    public var detail: String? = nil

    /// The proposed value as one line.
    public var title: String {
        switch value {
        case .phone(let text), .email(let text), .website(let text), .address(let text), .facility(let text):
            return text
        case .link(let link):
            return "\(link.kind): \(link.url)"
        case .price(let price):
            return Self.summary(of: price)
        case .opening(let rules, _):
            return ParkOpeningReader.summary(of: rules)
        case .openingNote(let text):
            return text
        case .event(let exception):
            return ParkEventReader.summary(of: exception)
        }
    }

    static func summary(of price: ParkPrice) -> String {
        let options = price.options.map { option -> String in
            var text = [option.currency, option.amount].compactMap { $0 }.joined(separator: " ")
            if let per = option.per { text += " / \(per)" }
            if let note = option.note { text += " (\(note))" }
            return text
        }
        return options.isEmpty ? price.name : "\(price.name): " + options.joined(separator: ", ")
    }
}

/// A question the person can answer, always about one field of the closed list.
public enum ParkImportQuestion: Equatable, Sendable, Identifiable {
    /// Nothing was found for this field, and the park has nothing either: another source may help.
    case missing(ParkImportField)

    public var id: String {
        switch self {
        case .missing(let field): "missing-\(field.rawValue)"
        }
    }
}

public enum ParkImportMerge {
    /// The fields that matter enough to ask about when nothing was found.
    static let askedFields: [ParkImportField] = [.phone, .email, .address, .prices, .opening]

    /// What would change in `park`: new values and different values. A value the park already has is left out.
    public static func items(
        from candidates: ParkImportCandidates, in park: Park, grounding: ParkImportGrounding
    ) -> [ParkImportItem] {
        var items: [ParkImportItem] = []
        func scalar(_ field: ParkImportField, _ new: String?, _ old: String?, _ value: (String) -> ParkImportItem.Value, _ found: (String) -> Bool) {
            guard let new = trimmed(new), !same(new, old) else { return }
            items.append(ParkImportItem(
                id: field.rawValue, field: field, value: value(new), previous: trimmed(old), level: found(new) ? .verified : .notFound
            ))
        }
        scalar(.phone, candidates.phone, park.phone, { .phone($0) }, grounding.phone)
        scalar(.email, candidates.email, park.email, { .email($0) }, grounding.email)
        scalar(.website, candidates.website, park.website, { .website($0) }, grounding.url)
        scalar(.address, candidates.address, park.address, { .address($0) }, grounding.text)

        for link in candidates.links {
            let existing = (park.links ?? []).first { ParkLinkKinds.normalizedKey($0.kind) == ParkLinkKinds.normalizedKey(link.kind) }
            if let existing, same(existing.url, link.url) { continue }
            items.append(ParkImportItem(
                id: "link-" + ParkLinkKinds.normalizedKey(link.kind), field: .links, value: .link(link),
                previous: existing?.url, level: grounding.url(link.url) ? .verified : .notFound
            ))
        }
        for candidate in candidates.prices {
            let existing = (park.prices ?? []).first { ParkImportCandidates.sameName($0.name, candidate.price.name) }
            if let existing, existing.options == candidate.price.options { continue }
            let level = candidate.price.options.map { grounding.amount($0.amount ?? "", quote: candidate.quote) }.min() ?? .notFound
            items.append(ParkImportItem(
                id: "price-" + candidate.price.name.lowercased(), field: .prices, value: .price(candidate.price),
                previous: existing.map { ParkImportItem.summary(of: $0) }, level: level
            ))
        }
        for facility in candidates.facilities {
            guard !(park.facilities ?? []).contains(where: { ParkImportCandidates.sameName($0, facility) }) else { continue }
            items.append(ParkImportItem(
                id: "facility-" + facility.lowercased(), field: .facilities, value: .facility(facility),
                previous: nil, level: grounding.text(facility) ? .verified : .notFound
            ))
        }
        if let finding = candidates.opening {
            if finding.rules != park.opening?.rules {
                let previous = (park.opening?.rules).flatMap { rules -> String? in rules.isEmpty ? nil : ParkOpeningReader.summary(of: rules) }
                items.append(ParkImportItem(
                    id: "opening", field: .opening, value: .opening(rules: finding.rules, sourceURL: finding.sourceURL),
                    previous: previous, level: finding.isVerified ? .verified : .notFound, detail: finding.lines.joined(separator: "\n")
                ))
            }
        } else if let note = candidates.openingNote, !same(note, park.opening?.note) {
            items.append(ParkImportItem(
                id: "opening-note", field: .opening, value: .openingNote(note), previous: trimmed(park.opening?.note),
                level: .verified, detail: nil
            ))
        }
        let known = park.opening?.exceptions ?? []
        for event in candidates.events where !known.contains(where: { ParkEventReader.sameEvent($0, event.exception) }) {
            items.append(ParkImportItem(
                id: "event-" + ParkEventReader.start(event.exception) + "-" + (event.exception.label ?? "").lowercased(),
                field: .events, value: .event(event.exception), previous: nil, level: .verified, detail: event.line
            ))
        }
        return items
    }

    /// Writes the accepted items into a copy of `park`. The editor cleans the result when it saves.
    public static func apply(_ items: [ParkImportItem], to park: Park) -> Park {
        var park = park
        for item in items {
            switch item.value {
            case .phone(let text): park.phone = text
            case .email(let text): park.email = text
            case .website(let text): park.website = text
            case .address(let text): park.address = text
            case .link(let link):
                var links = park.links ?? []
                ParkLinkKinds.upsert(link, into: &links)
                park.links = links
            case .price(let price):
                var prices = park.prices ?? []
                if let index = prices.firstIndex(where: { ParkImportCandidates.sameName($0.name, price.name) }) {
                    prices[index] = price
                } else {
                    prices.append(price)
                }
                park.prices = prices
            case .opening(let rules, let sourceURL):
                var opening = park.opening ?? ParkOpening()
                opening.rules = rules
                if (opening.sourceURL ?? "").isEmpty { opening.sourceURL = sourceURL }
                park.opening = opening
            case .openingNote(let text):
                var opening = park.opening ?? ParkOpening()
                opening.note = String(text.prefix(ParkTextField.note.maxLength))
                park.opening = opening
            case .event(let exception):
                var opening = park.opening ?? ParkOpening()
                var exceptions = opening.exceptions ?? []
                if !exceptions.contains(where: { ParkEventReader.sameEvent($0, exception) }) { exceptions.append(exception) }
                opening.exceptions = exceptions
                park.opening = opening
            case .facility(let text):
                var facilities = park.facilities ?? []
                if !facilities.contains(where: { ParkImportCandidates.sameName($0, text) }) { facilities.append(text) }
                park.facilities = facilities
            }
        }
        return park
    }

    /// Fields with nothing in the park and nothing proposed. Answering means giving another source.
    public static func questions(items: [ParkImportItem], park: Park) -> [ParkImportQuestion] {
        askedFields.compactMap { field -> ParkImportQuestion? in
            let has: Bool
            switch field {
            case .phone: has = !(park.phone ?? "").isEmpty
            case .email: has = !(park.email ?? "").isEmpty
            case .address: has = !(park.address ?? "").isEmpty
            case .prices: has = !(park.prices ?? []).isEmpty
            case .opening: has = park.opening?.hasSchedule == true
            default: has = true
            }
            return has || items.contains { $0.field == field } ? nil : .missing(field)
        }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func same(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs else { return false }
        return lhs.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
