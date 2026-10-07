import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Locale-independent, engineer-readable description of a network failure. `error.localizedDescription`
/// renders in the *device's* language (e.g. "geannuleerd" on a Dutch device for a cancelled request),
/// which makes debug logs cryptic and inconsistent across devices. This always reads in English and
/// names the likely cause instead of a bare status word.
func describeWaterTemperatureError(_ error: Error) -> String {
    guard let urlError = error as? URLError else {
        return "\(type(of: error)): \(error)"
    }
    switch urlError.code {
    case .cancelled:
        return "request was cancelled before completing — almost always means the fetch timeout budget "
            + "elapsed while waiting on the server, or a newer fetch superseded this one"
    case .timedOut:
        return "timed out at the network layer (slow or unresponsive connection)"
    case .notConnectedToInternet:
        return "device has no internet connection"
    case .networkConnectionLost:
        return "network connection was lost mid-request"
    case .cannotFindHost:
        return "DNS lookup failed (cannot find host)"
    case .cannotConnectToHost:
        return "cannot connect to host (server unreachable or refusing connections)"
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
        return "TLS/certificate failure"
    default:
        return "URLError \(urlError.code.rawValue) (\(urlError.code))"
    }
}

/// Rijkswaterstaat WaterWebServices ("OphalenLaatsteWaarnemingen") — CC0-licensed Dutch government
/// open data. Looks up the latest surface-water temperature at a station by its opaque code.
/// https://rijkswaterstaatdata.nl/waterdata/
public struct RWSWaterTemperatureClient: ParkWaterTemperatureFetching {
    public init() {}

    private static let endpoint = URL(
        string: "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES/OphalenLaatsteWaarnemingen"
    )!

    public func fetch(_ source: ParkWaterTemperatureSource) async -> ParkWaterTemperature? {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "AquoPlusWaarnemingMetadataLijst": [
                ["AquoMetadata": ["Compartiment": ["Code": "OW"], "Grootheid": ["Code": "T"]]]
            ],
            "LocatieLijst": [["Code": source.stationId]],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            WakeLog.error(.water, "RWS: failed to encode request body for station \(source.stationId)")
            return nil
        }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                WakeLog.warning(.water, "RWS: response for station \(source.stationId) was not HTTP")
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                let responseBody = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8 body>"
                WakeLog.error(
                    .water,
                    "RWS: station \(source.stationId) returned HTTP \(http.statusCode): \(responseBody)"
                )
                return nil
            }
            guard let reading = Self.parse(data) else {
                let responseBody = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8 body>"
                WakeLog.warning(
                    .water,
                    "RWS: station \(source.stationId) returned 200 but no parseable reading: \(responseBody)"
                )
                return nil
            }
            return reading
        } catch {
            let message = "RWS: request for station \(source.stationId) failed: \(describeWaterTemperatureError(error))"
            if (error as? URLError)?.code == .cancelled {
                WakeLog.warning(.water, message)
            } else {
                WakeLog.error(.water, message)
            }
            return nil
        }
    }

    private static func parse(_ data: Data) -> ParkWaterTemperature? {
        guard
            let decoded = try? JSONDecoder().decode(ObservationResponse.self, from: data),
            let observation = decoded.waarnemingenLijst?.first,
            let latest = observation.metingenLijst.max(by: { $0.tijdstip < $1.tijdstip }),
            let celsius = latest.meetwaarde.waardeNumeriek,
            let observedAt = makeTimestampFormatter().date(from: latest.tijdstip)
        else { return nil }
        return ParkWaterTemperature(
            celsius: celsius,
            observedAt: observedAt,
            stationName: observation.locatie.naam ?? observation.locatie.code,
            providerName: "Rijkswaterstaat"
        )
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private struct ObservationResponse: Decodable {
        let waarnemingenLijst: [Observation]?
        enum CodingKeys: String, CodingKey { case waarnemingenLijst = "WaarnemingenLijst" }
    }

    private struct Observation: Decodable {
        let locatie: Locatie
        let metingenLijst: [Meting]
        enum CodingKeys: String, CodingKey {
            case locatie = "Locatie"
            case metingenLijst = "MetingenLijst"
        }
    }

    private struct Locatie: Decodable {
        let code: String
        let naam: String?
        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case naam = "Naam"
        }
    }

    private struct Meting: Decodable {
        let tijdstip: String
        let meetwaarde: Meetwaarde
        enum CodingKeys: String, CodingKey {
            case tijdstip = "Tijdstip"
            case meetwaarde = "Meetwaarde"
        }
    }

    private struct Meetwaarde: Decodable {
        let waardeNumeriek: Double?
        enum CodingKeys: String, CodingKey { case waardeNumeriek = "Waarde_Numeriek" }
    }
}

/// KiWIS (Kisters) web service client shared by Belgium's two open-data water agencies, which
/// expose the identical REST API on different hosts/databases: MOW-HIC ("Hydrologisch
/// Informatiecentrum", navigable waterways — canals, tidal rivers) at hicws.vlaanderen.be, and
/// VMM (Vlaamse Milieumaatschappij, non-navigable waterways — smaller rivers/canals/watergangs)
/// at download.waterinfo.be. Both are free Flemish government open data, no token needed for
/// occasional queries (see https://waterinfo.vlaanderen.be). Looks up the latest surface
/// water-temperature reading for a station by its opaque `ts_id` (a KiWIS time-series id, not a
/// station code — a station can report several water-temperature series each).
public struct KiWISWaterTemperatureClient: ParkWaterTemperatureFetching {
    let endpoint: URL
    let logPrefix: String
    let providerName: String

    public init(endpoint: URL, logPrefix: String, providerName: String) {
        self.endpoint = endpoint
        self.logPrefix = logPrefix
        self.providerName = providerName
    }

    public func fetch(_ source: ParkWaterTemperatureSource) async -> ParkWaterTemperature? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "service", value: "kisters"),
            URLQueryItem(name: "type", value: "queryServices"),
            URLQueryItem(name: "request", value: "getTimeseriesValues"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "metadata", value: "true"),
            URLQueryItem(name: "period", value: "P1D"),
            URLQueryItem(name: "returnfields", value: "Timestamp,Value,Quality Code"),
            URLQueryItem(name: "ts_id", value: source.stationId),
        ]
        guard let url = components.url else {
            WakeLog.error(.water, "\(logPrefix): failed to build request URL for ts_id \(source.stationId)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                WakeLog.warning(.water, "\(logPrefix): response for ts_id \(source.stationId) was not HTTP")
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                let responseBody = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8 body>"
                WakeLog.error(
                    .water,
                    "\(logPrefix): ts_id \(source.stationId) returned HTTP \(http.statusCode): \(responseBody)"
                )
                return nil
            }
            guard let reading = parse(data) else {
                let responseBody = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8 body>"
                WakeLog.warning(
                    .water,
                    "\(logPrefix): ts_id \(source.stationId) returned 200 but no parseable reading: \(responseBody)"
                )
                return nil
            }
            return reading
        } catch {
            let message = "\(logPrefix): request for ts_id \(source.stationId) failed: \(describeWaterTemperatureError(error))"
            if (error as? URLError)?.code == .cancelled {
                WakeLog.warning(.water, message)
            } else {
                WakeLog.error(.water, message)
            }
            return nil
        }
    }

    private func parse(_ data: Data) -> ParkWaterTemperature? {
        guard
            let decoded = try? JSONDecoder().decode([KiWISTimeseries].self, from: data),
            let series = decoded.first,
            let latest = series.data.max(by: { $0.timestamp < $1.timestamp }),
            let observedAt = Self.makeTimestampFormatter().date(from: latest.timestamp)
        else { return nil }
        return ParkWaterTemperature(
            celsius: latest.value,
            observedAt: observedAt,
            stationName: series.stationName ?? series.tsId,
            providerName: providerName
        )
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private struct KiWISTimeseries: Decodable {
        let tsId: String
        let stationName: String?
        let data: [KiWISDataPoint]
        enum CodingKeys: String, CodingKey {
            case tsId = "ts_id"
            case stationName = "station_name"
            case data
        }
    }

    /// Each row is `[Timestamp, Value, "Quality Code"]` — a heterogeneous JSON array, not an
    /// object, per `returnfields` above. Only the first two columns are read.
    private struct KiWISDataPoint: Decodable {
        let timestamp: String
        let value: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            timestamp = try container.decode(String.self)
            value = try container.decode(Double.self)
        }
    }
}

/// Registry of the concrete fetchers, keyed by `ParkWaterTemperatureSource.provider`. Shared by the
/// phone (park screen) and the Watch (session-start estimate). A future
/// country adds an entry here, not a new abstraction.
public enum ParkWaterTemperatureFetchers {
    private static let fetchers: [String: any ParkWaterTemperatureFetching] = [
        "rws_nl": RWSWaterTemperatureClient(),
        "hic_be": KiWISWaterTemperatureClient(
            endpoint: URL(string: "https://hicws.vlaanderen.be/KiWIS/KiWIS")!,
            logPrefix: "HIC",
            providerName: "Vlaamse Waterweg"
        ),
        "vmm_be": KiWISWaterTemperatureClient(
            endpoint: URL(string: "https://download.waterinfo.be/tsmdownload/KiWIS/KiWIS")!,
            logPrefix: "VMM",
            providerName: "VMM"
        ),
    ]

    public static func fetcher(for provider: String) -> (any ParkWaterTemperatureFetching)? {
        fetchers[provider]
    }
}
