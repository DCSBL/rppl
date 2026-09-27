import Testing
@testable import RpplCore

@Suite(.serialized)
struct WakeLogTests {
    init() {
        WakeLog.clearHistory()
    }

    @Test
    func warningAndErrorAreRecordedNewestFirst() {
        WakeLog.warning(.water, "first")
        WakeLog.error(.water, "second")

        let entries = WakeLog.recentEntries()
        #expect(entries.count == 2)
        #expect(entries[0].message == "second")
        #expect(entries[0].level == .error)
        #expect(entries[1].message == "first")
        #expect(entries[1].level == .warning)
    }

    @Test
    func debugIsNotRecorded() {
        WakeLog.debug(.water, "not important")
        #expect(WakeLog.recentEntries().isEmpty)
    }

    @Test
    func historyIsCappedAtCapacity() {
        for index in 0..<250 {
            WakeLog.warning(.water, "entry \(index)")
        }
        let entries = WakeLog.recentEntries()
        #expect(entries.count == 200)
        #expect(entries.first?.message == "entry 249")
        #expect(entries.last?.message == "entry 50")
    }

    @Test
    func clearHistoryEmptiesEntries() {
        WakeLog.error(.sync, "boom")
        WakeLog.clearHistory()
        #expect(WakeLog.recentEntries().isEmpty)
    }

    @Test
    func formattedIncludesCategoryAndLevel() {
        WakeLog.error(.water, "station unreachable")
        let entry = WakeLog.recentEntries().first
        #expect(entry?.formatted.contains("water") == true)
        #expect(entry?.formatted.contains("FAIL") == true)
        #expect(entry?.formatted.contains("station unreachable") == true)
    }
}
