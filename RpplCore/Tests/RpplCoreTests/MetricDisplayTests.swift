import Foundation
import Testing
@testable import RpplCore

struct MetricDisplayTests {
    @Test func splitsNumberAndUnit() {
        #expect(MetricDisplay.split("42,2 km/h") == .init(value: "42,2", unit: "km/h"))
        #expect(MetricDisplay.split("14 km") == .init(value: "14", unit: "km"))
        #expect(MetricDisplay.split("398 kcal") == .init(value: "398", unit: "kcal"))
        #expect(MetricDisplay.split("19 °C") == .init(value: "19", unit: "°C"))
        #expect(MetricDisplay.split("10 sets") == .init(value: "10", unit: "sets"))
        #expect(MetricDisplay.split("~1,2 km") == .init(value: "~1,2", unit: "km"))
    }

    @Test func splitsOnNonBreakingSpaces() {
        #expect(MetricDisplay.split("42,2\u{00A0}km/h") == .init(value: "42,2", unit: "km/h"))
        #expect(MetricDisplay.split("1\u{202F}017 hPa") == .init(value: "1\u{202F}017", unit: "hPa"))
    }

    @Test func splitsNegativeNumbers() {
        #expect(MetricDisplay.split("-3 °C") == .init(value: "-3", unit: "°C"))
        #expect(MetricDisplay.split("−3 °C") == .init(value: "−3", unit: "°C"))
    }

    @Test func keepsCompoundAndUnitlessValuesWhole() {
        #expect(MetricDisplay.split("1 h, 49 min") == .init(value: "1 h, 49 min", unit: nil))
        #expect(MetricDisplay.split("1 uur, 49 min, 45 sec") == .init(value: "1 uur, 49 min, 45 sec", unit: nil))
        #expect(MetricDisplay.split("27%") == .init(value: "27%", unit: nil))
        #expect(MetricDisplay.split("--°") == .init(value: "--°", unit: nil))
        #expect(MetricDisplay.split("-") == .init(value: "-", unit: nil))
        #expect(MetricDisplay.split("") == .init(value: "", unit: nil))
    }

    #if canImport(Darwin) // DistanceFormat is Apple-only
    @Test func splitsRealFormatterOutput() {
        let nl = Locale(identifier: "nl_NL")
        let speed = MetricDisplay.split(DistanceFormat.kilometersPerHour(42.2, locale: nl))
        #expect(speed.value == "42,2")
        #expect(speed.unit != nil)

        let distance = MetricDisplay.split(DistanceFormat.kilometers(14_000, locale: nl))
        #expect(distance.value == "14")
        #expect(distance.unit != nil)
    }
    #endif

    @Test func fractionClampsToUnitRange() {
        #expect(abs(MetricDisplay.fraction(28.5, of: 42.2) - 0.6754) < 0.001)
        #expect(MetricDisplay.fraction(50, of: 40) == 1)
        #expect(MetricDisplay.fraction(-1, of: 10) == 0)
    }

    @Test func spanPlacesSegmentInsideRange() {
        let t0 = Date(timeIntervalSince1970: 0)
        let span = MetricDisplay.span(
            from: t0.addingTimeInterval(25),
            to: t0.addingTimeInterval(50),
            inRangeFrom: t0,
            to: t0.addingTimeInterval(100)
        )
        #expect(span == 0.25...0.5)
    }

    @Test func spanClampsToRangeAndHandlesEmptyRange() {
        let t0 = Date(timeIntervalSince1970: 0)
        let clamped = MetricDisplay.span(
            from: t0.addingTimeInterval(-10),
            to: t0.addingTimeInterval(200),
            inRangeFrom: t0,
            to: t0.addingTimeInterval(100)
        )
        #expect(clamped == 0...1)

        let empty = MetricDisplay.span(from: t0, to: t0.addingTimeInterval(5), inRangeFrom: t0, to: t0)
        #expect(empty == 0...0)
    }

    @Test func fractionIsZeroForInvalidInput() {
        #expect(MetricDisplay.fraction(1, of: 0) == 0)
        #expect(MetricDisplay.fraction(1, of: -5) == 0)
        #expect(MetricDisplay.fraction(.nan, of: 1) == 0)
        #expect(MetricDisplay.fraction(1, of: .infinity) == 0)
    }
}
