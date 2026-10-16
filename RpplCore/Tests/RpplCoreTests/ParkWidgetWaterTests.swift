import Foundation
import Testing
@testable import RpplCore

struct ParkWidgetWaterTests {
    private final class Fetcher: ParkWaterTemperatureFetching, @unchecked Sendable {
        var calls = 0
        var reading: ParkWaterTemperature?
        init(_ reading: ParkWaterTemperature?) { self.reading = reading }
        func fetch(_ source: ParkWaterTemperatureSource) async -> ParkWaterTemperature? {
            calls += 1
            return reading
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var park: Park {
        Park(id: "p", name: "P", location: ParkCoordinate(lat: 52, lon: 4),
             waterTemperature: ParkWaterTemperatureSource(provider: "rws_nl", stationId: "x"))
    }
    private func reading(at date: Date) -> ParkWaterTemperature {
        ParkWaterTemperature(celsius: 17.4, observedAt: date, stationName: "S", providerName: "RWS")
    }
    private func defaults(enabled: Bool = true) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        ParkWidgetWater.setEnabled(enabled, in: defaults)
        return defaults
    }

    @Test func fetchesOncePerIntervalPerPark() async {
        let defaults = defaults()
        let fetcher = Fetcher(reading(at: now))
        let first = await ParkWidgetWater.result(for: park, now: now, defaults: defaults, fetcher: fetcher, jitter: 0)
        let soon = await ParkWidgetWater.result(for: park, now: now.addingTimeInterval(3 * 3600), defaults: defaults, fetcher: fetcher, jitter: 0)
        #expect(fetcher.calls == 1)
        #expect(first.reading?.celsius == 17.4)
        #expect(soon.reading?.celsius == 17.4)
        _ = await ParkWidgetWater.result(for: park, now: now.addingTimeInterval(4 * 3600 + 1), defaults: defaults, fetcher: fetcher, jitter: 0)
        #expect(fetcher.calls == 2)
    }

    @Test func nextFetchIsNeverEarlierThanTheIntervalAndJitterIsCapped() {
        #expect(ParkWidgetWater.nextFetch(after: now, jitter: -5) == now.addingTimeInterval(4 * 3600))
        #expect(ParkWidgetWater.nextFetch(after: now, jitter: 99_999) == now.addingTimeInterval(4 * 3600 + 30 * 60))
    }

    @Test func offWithoutOptInOrStation() async {
        let fetcher = Fetcher(reading(at: now))
        let off = await ParkWidgetWater.result(for: park, now: now, defaults: defaults(enabled: false), fetcher: fetcher)
        let noStation = Park(id: "q", name: "Q", location: ParkCoordinate(lat: 52, lon: 4))
        let none = await ParkWidgetWater.result(for: noStation, now: now, defaults: defaults(), fetcher: fetcher)
        #expect(off.reading == nil && none.reading == nil)
        #expect(fetcher.calls == 0)
    }

    @Test func failedFetchKeepsOldReadingButStillWaits() async {
        let defaults = defaults()
        let fetcher = Fetcher(reading(at: now))
        _ = await ParkWidgetWater.result(for: park, now: now, defaults: defaults, fetcher: fetcher, jitter: 0)
        fetcher.reading = nil
        let later = now.addingTimeInterval(5 * 3600)
        let result = await ParkWidgetWater.result(for: park, now: later, defaults: defaults, fetcher: fetcher, jitter: 0)
        #expect(result.reading?.celsius == 17.4)
        #expect(result.nextFetch == later.addingTimeInterval(4 * 3600))
    }

    @Test func staleReadingIsDropped() async {
        let old = now.addingTimeInterval(-3 * 24 * 3600)
        let result = await ParkWidgetWater.result(for: park, now: now, defaults: defaults(), fetcher: Fetcher(reading(at: old)), jitter: 0)
        #expect(result.reading == nil)
    }
}
