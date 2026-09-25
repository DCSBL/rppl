import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func set(
    index: Int,
    duration: TimeInterval,
    distance: Double,
    speed: Double? = nil,
    laps: Int = 0
) -> SetSegmentStats {
    SetSegmentStats(
        index: index,
        startedAt: t0,
        endedAt: t0.addingTimeInterval(duration),
        duration: duration,
        distanceMeters: distance,
        lapCount: laps,
        sustainedSpeedKmh: speed
    )
}

private func location(
    at offset: TimeInterval,
    lat: Double = 52.0,
    lon: Double = 5.0,
    accuracy: Double = 10,
    speedKmh: Double
) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: accuracy,
        speed: SpeedUnits.metersPerSecond(fromKilometersPerHour: speedKmh)
    )
}

@Suite("HighlightAssigner")
struct HighlightAssignerTests {
    @Test func singleRideClearsHighlights() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 60, distance: 500, speed: 30)
        ])
        #expect(result[0].highlights.isEmpty)
    }

    @Test func allEqualDistanceNoLongest() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 40, distance: 100, speed: 20),
            set(index: 2, duration: 50, distance: 100, speed: 25),
        ])
        #expect(!result[0].highlights.contains(.longest))
        #expect(!result[1].highlights.contains(.longest))
        #expect(result[1].highlights.contains(.longestTime))
        #expect(result[1].highlights.contains(.fastest))
    }

    @Test func hideLongestTimeWhenSameAsLongest() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 120, distance: 900, speed: 20),
            set(index: 2, duration: 60, distance: 400, speed: 35),
        ])
        #expect(result[0].highlights == [.longest])
        #expect(result[1].highlights == [.fastest])
    }

    @Test func longestTimeWhenDifferentFromDistance() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 60, distance: 900, speed: 20),
            set(index: 2, duration: 120, distance: 400, speed: 25),
        ])
        #expect(result[0].highlights.contains(.longest))
        #expect(result[1].highlights.contains(.longestTime))
        #expect(result[1].highlights.contains(.fastest))
    }

    /// With two sets, "shortest" is just "the other one" — it needs a middle to mean anything.
    @Test func shortestNeedsThreeSets() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 120, distance: 900, speed: 30),
            set(index: 2, duration: 30, distance: 200, speed: 20),
        ])
        #expect(!result[1].highlights.contains(.shortest))
    }

    @Test func shortestGoesToTheShortestSet() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 120, distance: 900, speed: 30),
            set(index: 2, duration: 90, distance: 600, speed: 25),
            set(index: 3, duration: 30, distance: 200, speed: 20),
        ])
        #expect(result[2].highlights.contains(.shortest))
        #expect(!result[0].highlights.contains(.shortest))
        #expect(!result[1].highlights.contains(.shortest))
    }

    @Test func shortestSkippedWhenAllDurationsMatch() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 60, distance: 900, speed: 30),
            set(index: 2, duration: 60, distance: 600, speed: 25),
            set(index: 3, duration: 60, distance: 200, speed: 20),
        ])
        #expect(result.allSatisfy { !$0.highlights.contains(.shortest) })
    }

    /// Shortest in time can also be longest in distance; the distance badge wins, as with
    /// `longestTime`, so one set never carries two contradictory-looking time badges.
    @Test func shortestHiddenWhenSetAlsoWonDistance() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 30, distance: 900, speed: 40),
            set(index: 2, duration: 90, distance: 400, speed: 20),
            set(index: 3, duration: 120, distance: 500, speed: 25),
        ])
        #expect(result[0].highlights == [.longest, .fastest])
    }

    @Test func shortestOrdersAfterLongestTime() {
        #expect(HighlightAssigner.setOrder == [.longest, .longestTime, .shortest, .fastest])
    }

    @Test func sessionHidesMostWaterWhenSameAsLongest() {
        let map = HighlightAssigner.assignSessionHighlights([
            SessionHighlightInput(id: "a", totalDuration: 3600, ridingDuration: 2000, lapCount: 5),
            SessionHighlightInput(id: "b", totalDuration: 1800, ridingDuration: 1000, lapCount: 12),
        ])
        #expect(map["a"] == [.longest])
        #expect(map["b"] == [.mostLaps])
        #expect(map["a"]?.contains(.mostWaterTime) != true)
    }

    @Test func sessionMostWaterWhenDifferent() {
        let map = HighlightAssigner.assignSessionHighlights([
            SessionHighlightInput(id: "a", totalDuration: 3600, ridingDuration: 500, lapCount: 2),
            SessionHighlightInput(id: "b", totalDuration: 1800, ridingDuration: 1500, lapCount: 2),
        ])
        #expect(map["a"] == [.longest])
        #expect(map["b"] == [.mostWaterTime])
    }
}

@Suite("LocationSpeedStats.sustained")
struct SustainedSpeedTests {
    @Test func sustainedIgnoresSpikeAndLowAccuracy() {
        var samples: [LocationSample] = []
        for i in 0..<8 {
            samples.append(location(at: Double(i), speedKmh: 28))
        }
        // Spike + bad accuracy in the middle — must not win as a window mean.
        samples[3] = location(at: 3, accuracy: 80, speedKmh: 80)
        samples[4] = location(at: 4, speedKmh: 80)

        let sustained = LocationSpeedStats.sustainedSpeedKmh(from: samples)
        #expect(sustained != nil)
        #expect(abs((sustained ?? 0) - 28) < 1.0)
    }

    @Test func sustainedRequiresFiveSecondsSpan() {
        // 5 samples within 2 s — not a full window; falls back to mean of usable.
        let tight = (0..<5).map { i in
            location(at: Double(i) * 0.4, speedKmh: 30)
        }
        let fallback = LocationSpeedStats.sustainedSpeedKmh(from: tight)
        #expect(fallback != nil)
        #expect(abs((fallback ?? 0) - 30) < 0.5)

        // 5 samples over 5 s — full window.
        let wide = (0..<5).map { i in
            location(at: Double(i) * 1.25, speedKmh: 32)
        }
        let windowed = LocationSpeedStats.sustainedSpeedKmh(from: wide)
        #expect(windowed != nil)
        #expect(abs((windowed ?? 0) - 32) < 0.5)
    }

    @Test func sustainedGrowsPastFiveSamplesForSpan() {
        // 1 Hz would be fine; simulate 2 Hz so 5 samples = 2 s — need more samples.
        let samples = (0..<12).map { i in
            location(at: Double(i) * 0.5, speedKmh: 26 + Double(i % 3))
        }
        let sustained = LocationSpeedStats.sustainedSpeedKmh(from: samples)
        #expect(sustained != nil)
    }

    @Test func trimmedAverageDropsSlowTails() {
        // Slow start/end, fast middle with movement in lat.
        var samples: [LocationSample] = []
        samples.append(location(at: 0, lat: 52.0, lon: 5.0, speedKmh: 2))
        samples.append(location(at: 1, lat: 52.0, lon: 5.0, speedKmh: 3))
        for i in 0..<6 {
            samples.append(
                location(
                    at: Double(2 + i),
                    lat: 52.0 + Double(i) * 0.00005,
                    lon: 5.0,
                    speedKmh: 30
                )
            )
        }
        samples.append(location(at: 9, lat: 52.0003, lon: 5.0, speedKmh: 2))
        samples.append(location(at: 10, lat: 52.0003, lon: 5.0, speedKmh: 1))

        let trimmed = LocationSpeedStats.trimmedAverageSpeedKmh(locations: samples)
        let naive = LocationSpeedStats.averageSpeedKmh(
            distanceMeters: SessionStatsBuilder.distanceMeters(
                locations: samples,
                from: samples.first!.timestamp,
                to: samples.last!.timestamp,
                maxHorizontalAccuracyM: 25
            ),
            duration: 10
        )
        #expect(trimmed != nil)
        #expect(naive != nil)
        // Trimmed should be closer to cruise than whole-window avg diluted by tails.
        #expect((trimmed ?? 0) >= (naive ?? 0) - 0.1)
    }
}
