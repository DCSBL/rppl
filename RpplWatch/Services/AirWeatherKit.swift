import CoreLocation
import Foundation
import HealthKit
import RpplCore
import WeatherKit

/// WeatherKit current conditions mapped to HealthKit workout weather metadata.
enum AirWeatherKit {
    static let maxHorizontalAccuracyMeters: CLLocationAccuracy = 5_000
    static let fetchTimeout: TimeInterval = 8

    static func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy < maxHorizontalAccuracyMeters
    }

    static func fetch(location: CLLocation) async -> AirWeatherSnapshot? {
        do {
            return try await withTimeout(fetchTimeout) {
                let current = try await WeatherService.shared.weather(for: location).currentWeather
                return AirWeatherSnapshot(current: current)
            }
        } catch is CancellationError {
            return nil
        } catch is AirWeatherTimeoutError {
            WakeLog.debug(.workout, "WeatherKit timed out")
            return nil
        } catch {
            WakeLog.error(.workout, "WeatherKit: \(error.localizedDescription)")
            return nil
        }
    }

    private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AirWeatherTimeoutError()
            }
            guard let result = try await group.next() else {
                throw AirWeatherTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

struct AirWeatherTimeoutError: Error {}

struct AirWeatherSnapshot: Sendable {
    var celsius: Double
    var humidityPercent: Double
    var condition: HKWeatherCondition

    init(current: CurrentWeather) {
        celsius = current.temperature.converted(to: .celsius).value
        humidityPercent = current.humidity * 100
        condition = current.condition.healthKitWeatherCondition
    }

    var sessionWeather: SessionWeather {
        SessionWeather(temperatureCelsius: celsius, humidityPercent: humidityPercent)
    }

    var healthKitMetadata: [String: Any] {
        [
            HKMetadataKeyWeatherTemperature: HKQuantity(unit: .degreeCelsius(), doubleValue: celsius),
            HKMetadataKeyWeatherHumidity: HKQuantity(unit: .percent(), doubleValue: humidityPercent),
            HKMetadataKeyWeatherCondition: NSNumber(value: condition.rawValue),
        ]
    }
}

extension WeatherCondition {
    var healthKitWeatherCondition: HKWeatherCondition {
        switch self {
        case .clear, .hot:
            return .clear
        case .mostlyClear, .frigid:
            return .fair
        case .partlyCloudy:
            return .partlyCloudy
        case .mostlyCloudy:
            return .mostlyCloudy
        case .cloudy:
            return .cloudy
        case .foggy:
            return .foggy
        case .haze:
            return .haze
        case .windy:
            return .windy
        case .breezy:
            return .blustery
        case .smoky:
            return .smoky
        case .blowingDust:
            return .dust
        case .blizzard, .snow, .blowingSnow, .flurries, .sunFlurries, .heavySnow:
            return .snow
        case .hail:
            return .hail
        case .sleet:
            return .sleet
        case .wintryMix:
            return .mixedSnowAndSleet
        case .freezingDrizzle:
            return .freezingDrizzle
        case .freezingRain:
            return .freezingRain
        case .drizzle:
            return .drizzle
        case .rain, .heavyRain, .sunShowers:
            return .showers
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return .thunderstorms
        case .tropicalStorm:
            return .tropicalStorm
        case .hurricane:
            return .hurricane
        @unknown default:
            return .none
        }
    }
}
