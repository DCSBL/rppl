import Foundation
import Testing

@testable import RpplCore

struct ParkWaterTemperatureTests {
    private let estimate = ParkWaterTemperature(
        celsius: 17, observedAt: Date(), stationName: "Test", providerName: "Test"
    )

    @Test func estimateShownWhenNothingMeasured() {
        let display = WaterTemperatureDisplay.resolve(measuredAverage: nil, estimate: estimate)
        #expect(display == WaterTemperatureDisplay(celsius: 17, isEstimate: true))
    }

    @Test func measurementReplacesEstimate() {
        let display = WaterTemperatureDisplay.resolve(measuredAverage: 19.5, estimate: estimate)
        #expect(display == WaterTemperatureDisplay(celsius: 19.5, isEstimate: false))
    }

    @Test func nothingWithoutEitherSource() {
        #expect(WaterTemperatureDisplay.resolve(measuredAverage: nil, estimate: nil) == nil)
    }

    @Test func staleReadingIsNotFresh() {
        let now = Date()
        let old = ParkWaterTemperature(
            celsius: 10, observedAt: now.addingTimeInterval(-49 * 3600), stationName: "S", providerName: "P"
        )
        #expect(!old.isFresh(now: now))
        #expect(estimate.isFresh(now: now))
    }

    @Test func manifestRoundTripsEstimate() throws {
        var manifest = SessionManifest(testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "w", systemVersion: "1")
        manifest.waterTemperatureEstimate = estimate
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionManifest.self, from: encoder.encode(manifest))
        #expect(decoded.waterTemperatureEstimate?.celsius == 17)
    }

    private let rwsJSON = Data("""
        {"WaarnemingenLijst":[{"Locatie":{"Code":"x","Naam":"Hoek van Holland"},"MetingenLijst":[
        {"Tijdstip":"2026-07-01T10:00:00.000+02:00","Meetwaarde":{"Waarde_Numeriek":20.5}},
        {"Tijdstip":"2026-07-01T12:00:00.000+02:00","Meetwaarde":{"Waarde_Numeriek":21.5}},
        {"Tijdstip":"2026-07-01T14:00:00.000+02:00","Meetwaarde":{"Waarde_Numeriek":999999999}}]}]}
        """.utf8)

    @Test func rwsParsesLatestAndClosestAndSkipsMissingValues() throws {
        let noon = try #require(ISO8601DateFormatter().date(from: "2026-07-01T10:10:00Z"))
        #expect(RWSWaterTemperatureClient.parse(rwsJSON, target: nil)?.celsius == 21.5)
        let near = try #require(RWSWaterTemperatureClient.parse(rwsJSON, target: noon))
        #expect(near.celsius == 21.5)
        #expect(near.stationName == "Hoek van Holland")
        let early = noon.addingTimeInterval(-3 * 3600)
        #expect(RWSWaterTemperatureClient.parse(rwsJSON, target: early)?.celsius == 20.5)
    }

    @Test func kiwisParsesClosestToTarget() throws {
        let json = Data("""
            [{"ts_id":"1","station_name":"Knokke","data":[["2025-07-01T02:00:00.000+02:00",22.5],["2025-07-01T03:00:00.000+02:00",22.0]]}]
            """.utf8)
        let client = KiWISWaterTemperatureClient(endpoint: URL(string: "https://x.test")!, logPrefix: "T", providerName: "P")
        let target = try #require(ISO8601DateFormatter().date(from: "2025-07-01T00:50:00Z"))
        #expect(client.parse(json, target: target)?.celsius == 22.0)
        #expect(client.parse(json, target: nil)?.celsius == 22.0)
    }

    @Test func historyWindowIs24HoursEitherSide() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let window = ParkWaterTemperature.historyWindow(from: start, to: start.addingTimeInterval(3600))
        #expect(window.lowerBound == start.addingTimeInterval(-86_400))
        #expect(window.upperBound == start.addingTimeInterval(3600 + 86_400))
    }
}
