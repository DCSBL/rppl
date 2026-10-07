import Foundation

/// Pure validation and cable-trace helpers behind the park editor.
public enum ParkDraft {
    /// Something that stops a park from being saved. Problems are about the value that is there:
    /// an empty optional field is never an issue (see `isFilled`).
    public enum Issue: Equatable, Sendable {
        case missingName
        case invalidLocation
        case cableTooShort(index: Int)
        case invalidCablePoint(cable: Int)
        case invalidPhone
        case invalidEmail
        case invalidWebsite
        case priceNeedsName(index: Int)
        case priceNeedsAmount(index: Int)
        case linkNeedsKind(index: Int)
        case linkNeedsAddress(index: Int)
        case invalidLinkAddress(index: Int)
        case invalidTime(rule: Int)
        case invalidBlockTime(block: Int)

        /// The editor section to jump to when fixing this.
        public var section: ParkSection {
            switch self {
            case .missingName: .basics
            case .invalidLocation: .location
            case .cableTooShort, .invalidCablePoint: .cables
            case .invalidPhone, .invalidEmail, .invalidWebsite: .contact
            case .priceNeedsName, .priceNeedsAmount: .prices
            case .linkNeedsKind, .linkNeedsAddress, .invalidLinkAddress: .links
            case .invalidTime, .invalidBlockTime: .opening
            }
        }
    }

    public static func validate(_ park: Park) -> [Issue] {
        var issues: [Issue] = []
        if park.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.missingName) }
        if !isValid(park.location) { issues.append(.invalidLocation) }
        for (index, cable) in (park.cables ?? []).enumerated() {
            let points = cable.points ?? []
            // A cable without traced points is allowed (imagery is not always good enough); one point is not a line.
            if points.count == 1 { issues.append(.cableTooShort(index: index)) }
            if points.contains(where: { !isValid($0.coordinate) }) { issues.append(.invalidCablePoint(cable: index)) }
        }
        if let phone = park.phone, ParkText.phoneIssue(phone) != nil { issues.append(.invalidPhone) }
        if let email = park.email, ParkText.emailIssue(email) != nil { issues.append(.invalidEmail) }
        if let website = park.website, !website.isEmpty, ParkText.normalizedWebAddress(website) == nil {
            issues.append(.invalidWebsite)
        }
        for (index, price) in (park.prices ?? []).enumerated() {
            if price.name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.priceNeedsName(index: index)) }
            if price.options.isEmpty || price.options.contains(where: { ($0.amount ?? "").isEmpty }) {
                issues.append(.priceNeedsAmount(index: index))
            }
        }
        for (index, link) in (park.links ?? []).enumerated() {
            if link.kind.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.linkNeedsKind(index: index)) }
            if link.url.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(.linkNeedsAddress(index: index))
            } else if ParkText.normalizedWebAddress(link.url) == nil {
                issues.append(.invalidLinkAddress(index: index))
            }
        }
        for (index, rule) in (park.opening?.rules ?? []).enumerated()
        where ParkClock.minutes(rule.open) == nil || ParkClock.minutes(rule.close) == nil {
            issues.append(.invalidTime(rule: index))
        }
        for (index, slot) in (park.opening?.slots ?? []).enumerated()
        where ParkSchedule.minutes(slot.start) == nil || ParkSchedule.minutes(slot.end) == nil {
            issues.append(.invalidBlockTime(block: index))
        }
        return issues
    }

    /// Whether the section has anything in it. Used for the check marks in the editor and the review
    /// step; an empty section is fine, it just stays unknown in the app.
    public static func isFilled(_ section: ParkSection, in park: Park) -> Bool {
        switch section {
        case .basics: !park.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .location: isValid(park.location)
        case .contact: [park.phone, park.email, park.website].contains { !($0 ?? "").isEmpty }
        case .about: !(park.description ?? "").isEmpty || !(park.facilities ?? []).isEmpty
        case .cables: !(park.cables ?? []).isEmpty
        case .opening: park.opening?.hasSchedule == true
        case .prices: !(park.prices ?? []).isEmpty
        case .links: !(park.links ?? []).isEmpty
        }
    }

    /// The park as it is written to disk: text cleaned and trimmed, empty optionals dropped, list
    /// rows that were left empty removed, lists past their limits cut, a link with a web address
    /// completed (`https://`). The editor works on loose text; this makes it tidy.
    public static func finalized(_ park: Park) -> Park {
        var park = park
        park.name = ParkText.finalize(park.name, field: .name) ?? ""
        park.author = ParkText.finalize(park.author, field: .author)
        park.address = ParkText.finalize(park.address, field: .address)
        var seenLanguages = Set<String>()
        let languages = (park.languages ?? []).filter { ParkLanguage.isValidTag($0) && seenLanguages.insert($0.lowercased()).inserted }
        park.languages = languages.isEmpty ? nil : languages
        park.description = ParkText.finalize(park.description, field: .description)
        park.phone = ParkText.finalize(park.phone, field: .phone)
        park.email = ParkText.finalize(park.email, field: .email)
        park.website = ParkText.finalize(park.website, field: .url).map { ParkText.normalizedWebAddress($0) ?? $0 }

        let facilities = (park.facilities ?? []).compactMap { ParkText.finalize($0, field: .facility) }
        var seenFacilities = Set<String>()
        let uniqueFacilities = facilities.filter { seenFacilities.insert($0.lowercased()).inserted }
        park.facilities = uniqueFacilities.isEmpty ? nil : Array(uniqueFacilities.prefix(ParkLimits.facilities))

        let cables = (park.cables ?? []).map { cable -> ParkCable in
            var cable = cable
            cable.name = ParkText.finalize(cable.name, field: .label)
            cable.description = ParkText.finalize(cable.description, field: .cableDescription)
            if let length = cable.lengthM, length <= 0 { cable.lengthM = nil }
            return cable
        }
        park.cables = cables.isEmpty ? nil : Array(cables.prefix(ParkLimits.cables))

        let prices = (park.prices ?? []).map { price -> ParkPrice in
            var price = price
            price.name = ParkText.finalize(price.name, field: .label) ?? ""
            price.options = price.options.prefix(ParkLimits.priceOptions).map { option in
                var option = option
                option.per = ParkText.finalize(option.per, field: .label)
                option.note = ParkText.finalize(option.note, field: .note)
                option.perByLanguage = Self.finalizeVariants(option.perByLanguage, field: .label)
                option.noteByLanguage = Self.finalizeVariants(option.noteByLanguage, field: .note)
                option.currency = option.currency.flatMap { $0.isEmpty ? nil : $0.uppercased() }
                option.amount = option.amount.flatMap { text in
                    if case .amount(let parsed) = ParkPriceParser.parse(text) { return parsed.text }
                    return text.isEmpty ? nil : text
                }
                return option
            }.filter { !$0.isBlank }
            return price
        }.filter { !$0.name.isEmpty || !$0.options.isEmpty }
        park.prices = prices.isEmpty ? nil : Array(prices.prefix(ParkLimits.prices))

        var links: [ParkLink] = []
        for link in (park.links ?? []) where !link.kind.trimmingCharacters(in: .whitespaces).isEmpty
            || !link.url.trimmingCharacters(in: .whitespaces).isEmpty {
            let kind = ParkText.finalize(link.kind, field: .label) ?? ""
            let url = ParkText.finalize(link.url, field: .url).map { ParkText.normalizedWebAddress($0) ?? $0 } ?? ""
            ParkLinkKinds.upsert(ParkLink(kind: kind, url: url), into: &links)
        }
        park.links = links.isEmpty ? nil : Array(links.prefix(ParkLimits.links))

        if var opening = park.opening {
            opening.note = ParkText.finalize(opening.note, field: .note)
            let rules: [ParkOpeningRule] = (opening.rules ?? []).prefix(ParkLimits.rules).map { rule in
                var rule = rule
                rule.label = ParkText.finalize(rule.label, field: .label)
                rule.note = ParkText.finalize(rule.note, field: .note)
                rule.months = rule.months?.isEmpty == true ? nil : rule.months
                rule.days = rule.days?.isEmpty == true ? nil : rule.days
                rule.dates = tidyDates(rule.dates)
                return rule
            }
            opening.rules = rules.isEmpty ? nil : rules
            let slots: [ParkSlot] = (opening.slots ?? []).prefix(ParkLimits.slots).map { slot in
                var slot = slot
                slot.label = ParkText.finalize(slot.label, field: .label)
                slot.months = slot.months?.isEmpty == true ? nil : slot.months
                slot.days = slot.days?.isEmpty == true ? nil : slot.days
                slot.dates = tidyDates(slot.dates)
                return slot
            }
            opening.slots = slots.isEmpty ? nil : slots
            let isEmpty = opening.booking == nil && opening.rules == nil && opening.slots == nil
                && opening.note == nil && opening.bookingMinutes == nil && opening.exceptions == nil
            park.opening = isEmpty ? nil : opening
        }
        return park
    }

    /// Real dates only, each once, oldest first. Nothing left is nil.
    /// Cleans each language variant, drops blank ones and keys that are not language tags.
    private static func finalizeVariants(_ variants: [String: String]?, field: ParkTextField) -> [String: String]? {
        let cleaned = (variants ?? [:]).reduce(into: [String: String]()) { result, entry in
            guard ParkLanguage.isValidTag(entry.key), let text = ParkText.finalize(entry.value, field: field) else { return }
            result[entry.key] = text
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func tidyDates(_ dates: [String]?) -> [String]? {
        guard let dates else { return nil }
        let tidy = Array(Set(dates.filter(ParkDateText.isValid))).sorted().prefix(ParkLimits.dates)
        return tidy.isEmpty ? nil : Array(tidy)
    }

    public static func isValid(_ coordinate: ParkCoordinate) -> Bool {
        (-90...90).contains(coordinate.lat) && (-180...180).contains(coordinate.lon)
            && !(coordinate.lat == 0 && coordinate.lon == 0)
    }

    public static func append(_ coordinate: ParkCoordinate, to cable: inout ParkCable) {
        var points = cable.points ?? []
        points.append(ParkCablePoint(lat: coordinate.lat, lon: coordinate.lon))
        cable.points = points
    }

    public static func undo(_ cable: inout ParkCable) {
        guard var points = cable.points, !points.isEmpty else { return }
        points.removeLast()
        cable.points = points.isEmpty ? nil : points
    }

    public static func remove(_ cable: inout ParkCable, index: Int) {
        guard var points = cable.points, points.indices.contains(index) else { return }
        points.remove(at: index)
        cable.points = points.isEmpty ? nil : points
    }

    public static func move(_ cable: inout ParkCable, index: Int, to coordinate: ParkCoordinate) {
        guard var points = cable.points, points.indices.contains(index) else { return }
        points[index].lat = coordinate.lat
        points[index].lon = coordinate.lon
        cable.points = points
    }

    public static func toggleStart(_ cable: inout ParkCable, index: Int) {
        guard var points = cable.points, points.indices.contains(index) else { return }
        points[index].start = points[index].start == true ? nil : true
        cable.points = points
    }

    /// Centroid of the traced points, for placing a new park's pin.
    public static func centroid(of cables: [ParkCable]) -> ParkCoordinate? {
        let points = cables.flatMap { $0.points ?? [] }
        guard !points.isEmpty else { return nil }
        return ParkCoordinate(
            lat: points.map(\.lat).reduce(0, +) / Double(points.count),
            lon: points.map(\.lon).reduce(0, +) / Double(points.count)
        )
    }
}
