import CoreLocation
import RpplCore
import WeatherKit

/// Air conditions for a session in the past, from WeatherKit's hourly history: the hour nearest the
/// session's midpoint. Best effort: Apple only keeps history back to 2022-08-01 and the hourly
/// history is patchy, so any miss just means no weather tile.
enum ManualSessionWeather {
    private static let historyStart = Date(timeIntervalSince1970: 1_659_312_000)

    static func fetch(at spot: ParkCoordinate, from start: Date, to end: Date) async -> SessionWeather? {
        guard start >= historyStart, end <= .now else { return nil }
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        let location = CLLocation(latitude: spot.lat, longitude: spot.lon)
        do {
            return try await Deadline.run(8, label: "pastWeather") {
                let hours = try await WeatherService.shared.weather(
                    for: location,
                    including: .hourly(startDate: midpoint.addingTimeInterval(-3_600), endDate: midpoint.addingTimeInterval(3_600))
                )
                guard let hour = hours.forecast.min(by: {
                    abs($0.date.timeIntervalSince(midpoint)) < abs($1.date.timeIntervalSince(midpoint))
                }) else { return nil }
                return SessionWeather(
                    temperatureCelsius: hour.temperature.converted(to: .celsius).value,
                    humidityPercent: hour.humidity * 100,
                    windSpeedKmh: hour.wind.speed.converted(to: .kilometersPerHour).value,
                    windDirectionDegrees: hour.wind.direction.converted(to: .degrees).value,
                    precipitationMmPerHour: hour.precipitationAmount.converted(to: .millimeters).value
                )
            }
        } catch {
            WakeLog.debug(.ui, "past weather: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches and stores the weather, then tells the logbook to reload. Runs after the editor closed.
    @MainActor
    static func refresh(store: SessionFileStore, sessionId: String, at spot: ParkCoordinate, from start: Date, to end: Date) async {
        guard let weather = await fetch(at: spot, from: start, to: end) else { return }
        try? await StoreIO.runOffMain { try store.updateWeather(weather, sessionId: sessionId) }
        PhoneConnectivityService.shared.bumpSessionsRevision()
    }
}
