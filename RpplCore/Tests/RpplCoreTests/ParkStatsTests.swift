import Foundation
import Testing
@testable import RpplCore

struct ParkStatsTests {
    private func park(_ id: String, _ cables: [ParkCable]?) -> Park {
        Park(id: id, name: id, location: ParkCoordinate(lat: 52, lon: 5), cables: cables)
    }

    @Test func countsCablesPerDirectionAndSumsLengths() {
        let parks = [
            park("a", [
                ParkCable(direction: .counterClockwise, lengthM: 700),
                ParkCable(direction: .twoPointZero, lengthM: 150),
            ]),
            park("b", [ParkCable(direction: .clockwise, lengthM: 500)]),
            park("c", [ParkCable(direction: .counterClockwise)]),
            park("d", nil),
        ]
        let stats = ParkStats(parks: parks)
        #expect(stats.parkCount == 4)
        #expect(stats.cableCount == 4)
        #expect(stats.counterClockwise == 2)
        #expect(stats.clockwise == 1)
        #expect(stats.twoPointZero == 1)
        #expect(stats.totalLengthM == 1350)
    }

    @Test func untracedCableAddsNoLengthAndNoDirectionCountsOnlyAsCable() {
        let stats = ParkStats(parks: [park("a", [ParkCable()])])
        #expect(stats.cableCount == 1)
        #expect(stats.totalLengthM == 0)
        #expect(stats.counterClockwise + stats.clockwise + stats.twoPointZero == 0)
    }

    @Test func visitedParksAreDistinctAndFilterByYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ year: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
        }
        let sessions: [(date: Date, parkId: String?)] = [
            (date(2026), "a"), (date(2026), "a"), (date(2026), "b"), (date(2025), "c"), (date(2026), nil),
        ]
        #expect(ParkStats.visitedParkCount(sessions: sessions, calendar: calendar) == 3)
        #expect(ParkStats.visitedParkCount(sessions: sessions, year: 2026, calendar: calendar) == 2)
        #expect(ParkStats.visitedParkCount(sessions: sessions, year: 2024, calendar: calendar) == 0)
    }
}
