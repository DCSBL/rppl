import Foundation

/// Sunset for opening hours written as `close: sunset` (many cable parks close at dusk).
/// NOAA general solar calculation; accurate to a couple of minutes, which is plenty for opening hours.
public enum ParkSun {
    /// Local minutes after midnight of sunset at `coordinate` on the calendar day `date` falls on
    /// in `timeZone`. `nil` when the sun does not set that day (polar day / night).
    public static func sunsetMinute(at coordinate: ParkCoordinate, on date: Date, timeZone: TimeZone) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: noon)
        else { return nil }

        let gamma = 2 * Double.pi / 365 * Double(dayOfYear - 1)
        let equationOfTime = 229.18 * (
            0.000075
                + 0.001868 * cos(gamma)
                - 0.032077 * sin(gamma)
                - 0.014615 * cos(2 * gamma)
                - 0.040849 * sin(2 * gamma)
        )
        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let latitude = coordinate.lat * .pi / 180
        // 90.833° = sun's upper limb at the horizon, including atmospheric refraction.
        let zenith = 90.833 * Double.pi / 180
        let cosHourAngle = cos(zenith) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)
        guard (-1.0...1.0).contains(cosHourAngle) else { return nil }
        let hourAngleDegrees = acos(cosHourAngle) * 180 / .pi

        let utcMinutes = 720 - 4 * (coordinate.lon - hourAngleDegrees) - equationOfTime
        let offsetMinutes = Double(timeZone.secondsFromGMT(for: noon)) / 60
        return Int((utcMinutes + offsetMinutes).rounded())
    }
}
