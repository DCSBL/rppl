import Foundation
import RpplCore

/// The words and numbers of the editor, made from the park data in the person's own language and
/// number format (€12,34 or $12.34).
extension ParkFormatting {
    // MARK: Links

    static func linkKind(_ kind: String) -> String {
        switch ParkLinkKinds.normalizedKey(kind) {
        case ParkLinkKinds.booking: String(localized: "Booking page")
        case ParkLinkKinds.instagram: "Instagram"
        case ParkLinkKinds.facebook: "Facebook"
        case ParkLinkKinds.youtube: "YouTube"
        case ParkLinkKinds.tiktok: "TikTok"
        case ParkLinkKinds.contact: String(localized: "Contact page")
        case ParkLinkKinds.openingHours: String(localized: "Opening hours")
        case ParkLinkKinds.webcam: String(localized: "Webcam")
        default: kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }

    // MARK: Prices

    /// "€12.50" or "12,50 €", per the device's region. nil while the price has no amount.
    static func price(_ price: ParkPrice) -> String? {
        guard let amount = price.amount else { return nil }
        return amount.formatted(.currency(code: price.currency ?? defaultCurrencyCode))
    }

    static var defaultCurrencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    /// What goes back into the price field when an existing price is opened.
    static func priceInputText(_ price: ParkPrice) -> String {
        guard let amount = price.amount else { return "" }
        return amount.formatted(.currency(code: price.currency ?? defaultCurrencyCode).presentation(.narrow))
    }

    /// "per person", "90 minutes", or both, from the structured fields.
    static func priceQualifier(_ price: ParkPrice) -> String? {
        var parts: [String] = []
        if let per = price.per {
            switch per {
            case ParkPriceUnit.person: parts.append(String(localized: "per person"))
            case ParkPriceUnit.hour: parts.append(String(localized: "per hour"))
            case ParkPriceUnit.day: parts.append(String(localized: "per day"))
            case ParkPriceUnit.session: parts.append(String(localized: "per session"))
            default: parts.append(String(localized: "per \(per)"))
            }
        }
        if let minutes = price.minutes, minutes > 0 { parts.append(Self.minutes(minutes)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One line under a price in the editor.
    static func priceSummary(_ price: ParkPrice) -> String? {
        let parts = [Self.price(price), priceQualifier(price), price.note].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "1 hour, 30 minutes", "45 minutes".
    static func minutes(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    static func currencyName(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(code) · \(name)"
    }

    // MARK: Cables

    static func cableSummary(_ cable: ParkCable) -> String {
        var parts: [String] = []
        if let type = cableType(cable.direction) { parts.append(type) }
        if let direction = loopDirection(cable.direction) { parts.append(direction) }
        if let length = cable.effectiveLengthM { parts.append(DistanceFormat.meters(length)) }
        let count = cable.points?.count ?? 0
        parts.append(count == 0 ? String(localized: "Not traced yet") : String(localized: "\(count) points"))
        return parts.joined(separator: " · ")
    }

    // MARK: Opening hours

    static func monthsSummary(_ months: [Int]?) -> String {
        let selection = ParkDaySelection.monthSet(from: months)
        if selection.count == 12 { return String(localized: "All year") }
        let symbols = Calendar.current.shortStandaloneMonthSymbols
        var runs: [[Int]] = []
        for month in selection.sorted() {
            if let last = runs.last?.last, last + 1 == month {
                runs[runs.count - 1].append(month)
            } else {
                runs.append([month])
            }
        }
        return runs.map { run in
            if run.count >= 3, let first = run.first, let last = run.last {
                return "\(symbols[first - 1])–\(symbols[last - 1])"
            }
            return run.map { symbols[$0 - 1] }.joined(separator: ", ")
        }.joined(separator: ", ")
    }

    /// "Monday" for `mon`.
    static func longDayName(_ token: String) -> String {
        let order = ParkDaySelection.weekdayTokens
        guard let index = order.firstIndex(of: token.lowercased()) else { return token }
        // Calendar.weekdaySymbols starts on Sunday.
        return Calendar.current.weekdaySymbols[(index + 1) % 7].capitalized
    }

    private static func selectorDetails(
        months: [Int]?,
        days: [String]?,
        from: String?,
        until: String?,
        dates: [String]?
    ) -> [String] {
        var parts: [String] = []
        if let months, !months.isEmpty { parts.append(monthsSummary(months)) }
        if let days = Self.days(days) { parts.append(days) }
        if let from { parts.append(String(localized: "from \(ParkEditorDates.shortDate(from))")) }
        if let until { parts.append(String(localized: "until \(ParkEditorDates.shortDate(until))")) }
        if let dates, !dates.isEmpty { parts.append(String(localized: "\(dates.count) dates")) }
        return parts
    }

    static func ruleSummary(_ rule: ParkOpeningRule) -> (title: String, detail: String?) {
        let close = rule.close.lowercased() == ParkClock.sunset ? ParkClock.sunset : rule.close
        var parts: [String] = []
        if let label = rule.label { parts.append(label) }
        parts += selectorDetails(months: rule.months, days: rule.days, from: rule.from, until: rule.until, dates: rule.dates)
        if parts.isEmpty { parts.append(String(localized: "Every day, all year")) }
        return ("\(rule.open) – \(close)", parts.joined(separator: " · "))
    }

    static func blockSummary(_ slot: ParkSlot, numbered: Bool?) -> (title: String, detail: String?) {
        var parts: [String] = []
        if let label = slot.label {
            parts.append(label)
        } else if numbered != false, !slot.id.isEmpty {
            parts.append(String(localized: "Block \(slot.id)"))
        }
        parts += selectorDetails(months: slot.months, days: slot.days, from: slot.from, until: slot.until, dates: slot.dates)
        return (Self.slot(slot), parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    // MARK: Editor pages

    /// One line on what is in a page, for the list of pages.
    static func pageSummary(_ page: ParkEditorPage, park: Park) -> String {
        let empty = String(localized: "Not filled in yet")
        switch page {
        case .basics:
            let parts = [park.name, park.address ?? ""].filter { !$0.isEmpty }
            return parts.isEmpty ? empty : parts.joined(separator: " · ")
        case .contact:
            let parts = [park.phone, park.email, park.website].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? empty : parts.joined(separator: " · ")
        case .about:
            var parts: [String] = []
            if park.description?.isEmpty == false { parts.append(String(localized: "Description")) }
            if let facilities = park.facilities, !facilities.isEmpty { parts.append(facilities.joined(separator: ", ")) }
            return parts.isEmpty ? empty : parts.joined(separator: " · ")
        case .cables:
            guard let cables = park.cables, !cables.isEmpty else { return empty }
            let names = cables.enumerated().map { $0.element.name ?? String(localized: "Cable \($0.offset + 1)") }
            return names.joined(separator: ", ")
        case .opening:
            guard let opening = park.opening, opening.isScheduleKnown else {
                return String(localized: "Opening hours unknown")
            }
            var parts: [String] = []
            if let rules = opening.rules, !rules.isEmpty { parts.append(String(localized: "\(rules.count) opening periods")) }
            if let slots = opening.slots, !slots.isEmpty { parts.append(String(localized: "\(slots.count) blocks")) }
            return parts.joined(separator: " · ")
        case .prices:
            guard let prices = park.prices, !prices.isEmpty else { return empty }
            return String(localized: "\(prices.count) prices")
        case .links:
            guard let links = park.links, !links.isEmpty else { return empty }
            return links.map { linkKind($0.kind) }.joined(separator: ", ")
        }
    }
}

extension ParkDraft.Issue {
    /// What is wrong, in friendly words.
    var message: String {
        switch self {
        case .missingName: String(localized: "Give the park a name.")
        case .invalidLocation: String(localized: "Set the park's location on the map.")
        case .cableTooShort(let index): String(localized: "Cable \(index + 1) needs at least 2 traced points, or none.")
        case .invalidCablePoint(let index): String(localized: "Cable \(index + 1) has a point that is not a real place.")
        case .invalidPhone: String(localized: "Check the phone number.")
        case .invalidEmail: String(localized: "Check the email address.")
        case .invalidWebsite: String(localized: "Check the website address.")
        case .priceNeedsName(let index): String(localized: "Give price \(index + 1) a name.")
        case .priceNeedsAmount(let index): String(localized: "Price \(index + 1) has no amount yet. Fill it in or remove the price.")
        case .linkNeedsKind(let index): String(localized: "Choose what link \(index + 1) is.")
        case .linkNeedsAddress(let index): String(localized: "Link \(index + 1) has no address yet.")
        case .invalidLinkAddress(let index): String(localized: "Check the address of link \(index + 1).")
        case .invalidTime(let index): String(localized: "Opening hours \(index + 1) have a time we cannot read.")
        case .invalidBlockTime(let index): String(localized: "Block \(index + 1) has a time we cannot read.")
        }
    }
}
