import Foundation

extension Park {
    /// Town from the address: what follows the postcode ("8300 Knokke-Heist", "86316 Friedberg" → town),
    /// else the last comma part. `nil` without an address.
    public var cityName: String? {
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { return nil }
        if let range = address.range(of: #"\b\d{4,5}(?:\s?[A-Z]{2}\b)?\s+"#, options: .regularExpression) {
            let city = address[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !city.isEmpty { return city }
        }
        let last = address.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) }
        return (last?.isEmpty ?? true) ? nil : last
    }

    /// Country name in `locale`, from the park's time zone (the files carry no country field).
    /// shortcut: only the zones of countries with bundled parks; others give `nil`, add a zone when a park needs it.
    public func countryName(locale: Locale = .current) -> String? {
        let code: String? = switch resolvedTimeZone.identifier {
        case "Europe/Amsterdam": "NL"
        case "Europe/Brussels": "BE"
        case "Europe/Berlin": "DE"
        case "Europe/Paris": "FR"
        case "Europe/Luxembourg": "LU"
        default: nil
        }
        return code.flatMap { locale.localizedString(forRegionCode: $0) }
    }

    /// "Knokke-Heist, België", or whichever part is known.
    public func placeSubtitle(locale: Locale = .current) -> String? {
        let parts = [cityName, countryName(locale: locale)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
