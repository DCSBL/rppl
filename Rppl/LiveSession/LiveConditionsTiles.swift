import RpplCore
import SwiftUI

/// Water, air and wind at a park: the same sources and wording as the park screen. Shows only what loaded.
struct LiveConditionsTiles: View {
    let park: Park?

    @State private var weather: ParkWeather?
    @State private var water: ParkWaterTemperature?

    var body: some View {
        if park != nil {
            InfoTileGrid {
                if let water {
                    InfoTile("Water", metric: .water) { MetricValue(TemperatureFormat.celsius(water.celsius), size: .medium) }
                }
                if let weather {
                    InfoTile("Air", metric: .air) { MetricValue(TemperatureFormat.celsius(weather.temperatureCelsius), size: .medium) }
                    InfoTile("Wind", metric: .wind) {
                        MetricValue(
                            DistanceFormat.kilometersPerHour(weather.windKmh), size: .medium,
                            caption: LocalizedStringKey(CompassDirection8(degrees: weather.windDirectionDegrees).name)
                        )
                    }
                }
            }
            .task(id: park?.id) {
                guard let park else { return }
                async let loadedWeather = ParksWeatherProvider.shared.weather(for: park)
                async let loadedWater = ParkWaterTemperatureProvider.shared.temperature(for: park)
                weather = await loadedWeather
                water = await loadedWater
            }
        }
    }
}
