import Foundation
import Testing
@testable import RpplCore

struct DurationTotalTests {
    private let en = Locale(identifier: "en_US")

    @Test func hoursRoundToWholeNumber() {
        #expect(DurationFormat.total(37.2 * 3600, locale: en) == "37 hr")
    }

    @Test func underAnHourUsesMinutes() {
        #expect(DurationFormat.total(2400, locale: en) == "40 min")
        #expect(DurationFormat.total(0, locale: en) == "0 min")
    }
}
