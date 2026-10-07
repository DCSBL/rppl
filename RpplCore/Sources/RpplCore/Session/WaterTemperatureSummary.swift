import Foundation

/// Water temperature for display: a rolling mean over the latest samples, plus the session range.
///
/// A Watch worn under the wetsuit reads too warm until it is moved on top, so the whole-session
/// mean would keep the early wrong values forever. The rolling window forgets them as soon as
/// enough newer samples exist.
public struct WaterTemperatureSummary: Equatable, Sendable {
    /// Trailing window: at least this many samples *and* at least this much time.
    public static let windowMinimumSamples = 5
    public static let windowMinimumDuration: TimeInterval = 5 * 60
    /// Show a range only when min and max differ by more than this many °C.
    public static let rangeThresholdCelsius = 3.0

    /// Mean of the trailing window (all samples while the window cannot be filled yet).
    public var currentCelsius: Double
    public var minCelsius: Double
    public var maxCelsius: Double

    /// Min–max of the session when it spans more than `rangeThresholdCelsius`, else nil.
    public var range: ClosedRange<Double>? {
        maxCelsius - minCelsius > Self.rangeThresholdCelsius ? minCelsius...maxCelsius : nil
    }

    public init(currentCelsius: Double, minCelsius: Double, maxCelsius: Double) {
        self.currentCelsius = currentCelsius
        self.minCelsius = minCelsius
        self.maxCelsius = maxCelsius
    }

    public static func make(from samples: [WaterTemperatureSample]) -> WaterTemperatureSummary? {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard let last = sorted.last else { return nil }
        var start = sorted.count - 1
        while start > 0 {
            let count = sorted.count - start
            let span = last.timestamp.timeIntervalSince(sorted[start].timestamp)
            if count >= windowMinimumSamples, span >= windowMinimumDuration { break }
            start -= 1
        }
        let window = sorted[start...]
        let all = sorted.map(\.celsius)
        return WaterTemperatureSummary(
            currentCelsius: window.map(\.celsius).reduce(0, +) / Double(window.count),
            minCelsius: all.min() ?? last.celsius,
            maxCelsius: all.max() ?? last.celsius
        )
    }
}
