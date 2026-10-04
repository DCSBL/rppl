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

private func timedSet(index: Int, start: TimeInterval, end: TimeInterval) -> SetSegmentStats {
    SetSegmentStats(
        index: index,
        startedAt: t0.addingTimeInterval(start),
        endedAt: t0.addingTimeInterval(end),
        duration: end - start,
        distanceMeters: 500
    )
}

/// Session input whose original fields tie, so only the badge under test can win.
private func session(
    _ id: String,
    ratio: Double? = nil,
    sets: Int? = nil,
    distance: Double? = nil,
    topSpeed: Double? = nil,
    air: Double? = nil,
    wind: Double? = nil,
    rain: Double? = nil,
    water: Double? = nil,
    start: Double? = nil,
    end: Double? = nil
) -> SessionHighlightInput {
    SessionHighlightInput(
        id: id,
        totalDuration: 3600,
        ridingDuration: 1200,
        lapCount: 2,
        ridingInactiveRatio: ratio,
        setCount: sets,
        totalDistanceMeters: distance,
        topSpeedKmh: topSpeed,
        airTemperatureCelsius: air,
        windSpeedKmh: wind,
        precipitationMmPerHour: rain,
        waterTemperatureCelsius: water,
        startMinuteOfDay: start,
        endMinuteOfDay: end
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

    @Test func setOrderIsFixed() {
        #expect(HighlightAssigner.setOrder == [
            .longest, .longestTime, .shortest, .fastest, .mostLaps, .comeback, .backToBack,
        ])
    }

    @Test func mostLapsGoesToSetWithMostLaps() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 60, distance: 900, laps: 1),
            set(index: 2, duration: 90, distance: 600, laps: 3),
        ])
        #expect(result[1].highlights.contains(.mostLaps))
        #expect(!result[0].highlights.contains(.mostLaps))
    }

    @Test func mostLapsSkippedWhenNoLaps() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, duration: 60, distance: 900),
            set(index: 2, duration: 90, distance: 600),
        ])
        #expect(result.allSatisfy { !$0.highlights.contains(.mostLaps) })
    }

    @Test func comebackAndBackToBackFollowTheBreaks() {
        // Breaks before sets 2, 3, 4: 60 s, 600 s, 20 s.
        let result = HighlightAssigner.assignSetHighlights([
            timedSet(index: 1, start: 0, end: 100),
            timedSet(index: 2, start: 160, end: 260),
            timedSet(index: 3, start: 860, end: 960),
            timedSet(index: 4, start: 980, end: 1080),
        ])
        #expect(result[2].highlights.contains(.comeback))
        #expect(result[3].highlights.contains(.backToBack))
        #expect(!result[0].highlights.contains(.comeback))
        #expect(!result[0].highlights.contains(.backToBack))
        #expect(!result[1].highlights.contains(.comeback))
        #expect(!result[1].highlights.contains(.backToBack))
    }

    /// Two sets have one break: nothing to compare. Three sets have two: enough for a comeback,
    /// not yet for back to back (a "lowest" badge needs three values).
    @Test func breakBadgesNeedEnoughSets() {
        let two = HighlightAssigner.assignSetHighlights([
            timedSet(index: 1, start: 0, end: 100),
            timedSet(index: 2, start: 400, end: 500),
        ])
        #expect(two.allSatisfy { !$0.highlights.contains(.comeback) })

        let three = HighlightAssigner.assignSetHighlights([
            timedSet(index: 1, start: 0, end: 100),
            timedSet(index: 2, start: 400, end: 500),
            timedSet(index: 3, start: 520, end: 620),
        ])
        #expect(three[1].highlights.contains(.comeback))
        #expect(three.allSatisfy { !$0.highlights.contains(.backToBack) })
    }

    @Test func breakBadgesSkippedWhenBreaksMatch() {
        let result = HighlightAssigner.assignSetHighlights([
            timedSet(index: 1, start: 0, end: 100),
            timedSet(index: 2, start: 200, end: 300),
            timedSet(index: 3, start: 400, end: 500),
            timedSet(index: 4, start: 600, end: 700),
        ])
        #expect(result.allSatisfy { !$0.highlights.contains(.comeback) })
        #expect(result.allSatisfy { !$0.highlights.contains(.backToBack) })
    }

    @Test func unknownSetHighlightCodesAreDroppedOnDecode() throws {
        let json = """
        {"index":1,"startedAt":0,"endedAt":60,"duration":60,"distanceMeters":500,
         "highlights":["fastest","somethingFromTheFuture"]}
        """
        let decoded = try JSONDecoder().decode(SetSegmentStats.self, from: Data(json.utf8))
        #expect(decoded.highlights == [.fastest])
    }

    @Test func sessionOrderStartsWithTheOriginalBadges() {
        #expect(Array(HighlightAssigner.sessionOrder.prefix(6)) == [
            .longest, .mostWaterTime, .mostLaps, .highestRidePercentage, .mostCalories, .longestSetEver,
        ])
        #expect(Set(HighlightAssigner.sessionOrder) == Set(SessionHighlight.allCases))
        #expect(Set(HighlightAssigner.setOrder) == Set(SetHighlight.allCases))
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

    @Test func sessionHighestRidePercentageWinner() {
        let map = HighlightAssigner.assignSessionHighlights([
            SessionHighlightInput(
                id: "a", totalDuration: 3600, ridingDuration: 500, lapCount: 2,
                ridingInactiveRatio: 0.4
            ),
            SessionHighlightInput(
                id: "b", totalDuration: 1800, ridingDuration: 1500, lapCount: 2,
                ridingInactiveRatio: 0.9
            ),
        ])
        #expect(map["b"]?.contains(.highestRidePercentage) == true)
        #expect(map["a"]?.contains(.highestRidePercentage) != true)
    }

    @Test func sessionMostCaloriesWinner() {
        let map = HighlightAssigner.assignSessionHighlights([
            SessionHighlightInput(
                id: "a", totalDuration: 3600, ridingDuration: 500, lapCount: 2,
                totalEnergyKilocalories: 300
            ),
            SessionHighlightInput(
                id: "b", totalDuration: 1800, ridingDuration: 1500, lapCount: 2,
                totalEnergyKilocalories: 700
            ),
        ])
        #expect(map["b"]?.contains(.mostCalories) == true)
        #expect(map["a"]?.contains(.mostCalories) != true)
    }

    @Test func sessionMostCaloriesSkipsMissingValues() {
        let map = HighlightAssigner.assignSessionHighlights([
            SessionHighlightInput(id: "a", totalDuration: 3600, ridingDuration: 500, lapCount: 2),
            SessionHighlightInput(id: "b", totalDuration: 1800, ridingDuration: 1500, lapCount: 2),
        ])
        #expect(map["a"]?.contains(.mostCalories) != true)
        #expect(map["b"]?.contains(.mostCalories) != true)
    }

    @Test func sessionLongestSetEverWinner() {
        let map = HighlightAssigner.assignSessionHighlights([
            SessionHighlightInput(
                id: "a", totalDuration: 3600, ridingDuration: 500, lapCount: 2,
                longestSetDistanceMeters: 1200
            ),
            SessionHighlightInput(
                id: "b", totalDuration: 1800, ridingDuration: 1500, lapCount: 2,
                longestSetDistanceMeters: 2500
            ),
        ])
        #expect(map["b"]?.contains(.longestSetEver) == true)
        #expect(map["a"]?.contains(.longestSetEver) != true)
    }

    @Test func sessionMaxBadgesGoToTheWinner() {
        let map = HighlightAssigner.assignSessionHighlights([
            session("a", sets: 3, distance: 4000, topSpeed: 31, air: 12, wind: 8, rain: 0, end: 15 * 60),
            session("b", sets: 7, distance: 6000, topSpeed: 36, air: 24, wind: 30, rain: 1.2, end: 21 * 60),
        ])
        #expect(map["b"] == [.mostSets, .mostDistance, .topSpeed, .hottest, .windiest, .rainiest, .nightOwl])
        #expect(map["a"] == nil)
    }

    @Test func sessionMaxBadgesSkipTiesAndMissingValues() {
        let map = HighlightAssigner.assignSessionHighlights([
            session("a", sets: 4, air: 18),
            session("b", sets: 4),
            session("c"),
        ])
        #expect(map.isEmpty)
    }

    @Test func rainRiderNeedsActualRain() {
        let map = HighlightAssigner.assignSessionHighlights([
            session("a", rain: 0),
            session("b", rain: 0),
            session("c", rain: 0),
        ])
        #expect(map.isEmpty)
    }

    /// With two sessions a "lowest" badge is just "the other one", and one session would carry
    /// Coldest while the other carries Hottest.
    @Test func sessionMinBadgesNeedThreeValues() {
        let two = HighlightAssigner.assignSessionHighlights([
            session("a", ratio: 0.3, air: 5, water: 9, start: 8 * 60),
            session("b", ratio: 0.6, air: 20, water: 18, start: 14 * 60),
        ])
        #expect(two["a"] == nil)
        #expect(two["b"] == [.highestRidePercentage, .hottest])
    }

    @Test func sessionMinBadgesGoToTheLowest() {
        let map = HighlightAssigner.assignSessionHighlights([
            session("a", ratio: 0.3, air: 5, water: 9, start: 8 * 60),
            session("b", ratio: 0.6, air: 20, water: 18, start: 14 * 60),
            session("c", ratio: 0.5, air: 15, water: 14, start: 11 * 60),
        ])
        #expect(map["a"] == [.laziest, .coldest, .iceBath, .earlyBird])
        #expect(map["b"] == [.highestRidePercentage, .hottest])
        #expect(map["c"] == nil)
    }

    @Test func minutesOfDayCountsPastMidnightFromTheStartDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Amsterdam"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 21, minute: 30)))
        let end = start.addingTimeInterval(3 * 3600)

        let minutes = SessionHighlightInput.minutesOfDay(start: start, end: end, calendar: calendar)

        #expect(minutes.start == Double(21 * 60 + 30))
        #expect(try #require(minutes.end) == Double(24 * 60 + 30))
        #expect(SessionHighlightInput.minutesOfDay(start: start, end: nil, calendar: calendar).end == nil)
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
