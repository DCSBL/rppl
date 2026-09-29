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
}
