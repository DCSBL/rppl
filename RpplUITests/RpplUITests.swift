import XCTest

/// Key iPhone flows against the seeded logbook (`UITestFixtures`: 1 tracked + 3 manual sessions,
/// clock frozen at Sat 15 Aug 2026 12:30). Queries use English labels.
final class RpplUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        launch()
    }

    /// `sessions`: generated logbook size (`-rpplUITestSessions`); nil = the default seeded logbook.
    private func launch(sessions: Int? = nil, textSize: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        if let sessions { app.launchArguments += ["-rpplUITestSessions", String(sessions)] }
        app.launch()
    }

    private func chart(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func card(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    func testTabsSwitch() {
        XCTAssertTrue(app.staticTexts["Logbook"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Parks"].tap()
        XCTAssertTrue(app.staticTexts["Parks"].waitForExistence(timeout: 15))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Rppl"].waitForExistence(timeout: 15))
        app.navigationBars["Rppl"].buttons["Close"].tap()
        app.tabBars.buttons["Logbook"].tap()
        XCTAssertTrue(app.scrollToElement(card("Wakeboard, Project 7 Cablepark")))
    }

    @MainActor
    func testLogbookListsSeededSessions() {
        XCTAssertTrue(app.scrollToElement(card("Wakeboard, Project 7 Cablepark")))
        // Lazy list: on a small screen the lower cards are not built until scrolled into view.
        let zwolle = card("Wakeboard, Lakeside Zwolle")
        XCTAssertTrue(app.scrollToElement(zwolle))
        let groningen = card("Wakeboard, Wakepark Groningen")
        XCTAssertTrue(app.scrollToElement(groningen))
        XCTAssertTrue(app.staticTexts["4 total"].exists)
    }

    @MainActor
    func testOpenSessionDetailAndBack() {
        let zwolle = card("Wakeboard, Lakeside Zwolle")
        XCTAssertTrue(app.scrollToElement(zwolle))
        zwolle.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Zwolle'")).firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(zwolle.waitForExistence(timeout: 15))
    }

    @MainActor
    func testDeleteSessionBySwipe() {
        let groningen = card("Wakeboard, Lakeside Zwolle")
        XCTAssertTrue(app.scrollToElement(groningen))
        groningen.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete from Rppl"].tap()
        XCTAssertTrue(app.staticTexts["3 total"].waitForExistence(timeout: 15))
        XCTAssertFalse(groningen.exists)
    }

    @MainActor
    func testAddManualSession() {
        XCTAssertTrue(app.buttons["Add session"].waitForExistence(timeout: 30))
        app.buttons["Add session"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        save.tap()
        // The totals tile is one combined button; its label reads "5, Sessions".
        let sessions = total("logbook-total-sessions")
        XCTAssertTrue(sessions.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "label BEGINSWITH '5'"), evaluatedWith: sessions)
        waitForExpectations(timeout: 15)
    }

    /// Landscape iPhones are wide enough for two panes but still collapse the split view into one stack,
    /// so the map must stay reachable through the "View on map" segment.
    @MainActor
    func testParksMapOptionAvailableInLandscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone only")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app.tabBars.buttons["Parks"].tap()
        app.chooseParksSort("View on map")
        XCTAssertTrue(app.parksSortOptionExists("Nearby"))
    }

    @MainActor
    func testParksSearchOpensDetail() {
        app.tabBars.buttons["Parks"].tap()
        app.buttons["Search parks"].tap()
        let field = app.textFields["Search parks"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.typeText("Zwolle")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Zwolle'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor
    func testSeasonChartsHiddenUnderFiveSessions() {
        app.terminate()
        launch(sessions: 3)
        XCTAssertTrue(app.waitForSessionCount(3))
        XCTAssertFalse(chart("season-distance-chart").exists)
        XCTAssertFalse(chart("season-temperature-chart").exists)
    }

    @MainActor
    func testSeasonChartsShownWithEighteenSessions() {
        app.terminate()
        launch(sessions: 18)
        // The "18 total" header sits below the charts, so the lazy list never builds it on screen.
        let distance = chart("season-distance-chart")
        XCTAssertTrue(app.scrollToElement(distance))
        XCTAssertEqual(distance.value as? String, "18") // one bar per session
        XCTAssertGreaterThan(distance.frame.height, 50)

        // Accessibility text sizes swap the segments for a menu: open it, then pick the entry.
        let metricMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Distance & duration")).firstMatch
        if metricMenu.exists {
            metricMenu.tap()
        }
        app.buttons["Duration"].tap()
        XCTAssertEqual(chart("season-duration-chart").value as? String, "18")

        let temperature = chart("season-temperature-chart")
        app.scrollTo(temperature)
        XCTAssertTrue(temperature.exists)
        XCTAssertGreaterThan(temperature.frame.height, 100)
    }

    private func total(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Swapping max <-> average speed (tap) must not resize the totals text: the tile keeps its
    /// height, so the label neither wraps nor shrinks.
    private func assertSpeedSwapKeepsTextSize() {
        let speed = total("logbook-total-speed")
        XCTAssertTrue(speed.waitForExistence(timeout: 30))
        app.scrollTo(speed) // big text stacks the tiles; a tap on an off-screen tile lands elsewhere
        XCTAssertTrue(speed.label.contains("speed"))
        let before = speed.frame.height
        let labelBefore = speed.label
        speed.tap()
        XCTAssertNotEqual(speed.label, labelBefore, "tap should swap max/average")
        XCTAssertEqual(speed.frame.height, before, accuracy: 0.5)
        speed.tap()
        XCTAssertEqual(speed.frame.height, before, accuracy: 0.5)
    }

    @MainActor
    func testTotalsSpeedSwapKeepsTextSize() {
        assertSpeedSwapKeepsTextSize()
        let sessions = total("logbook-total-sessions")
        let speed = total("logbook-total-speed")
        // Big text stacks the tiles, where each one is as tall as its own content.
        if abs(speed.frame.minY - sessions.frame.minY) < 1 {
            XCTAssertEqual(speed.frame.height, sessions.frame.height, accuracy: 0.5)
        }
    }

    @MainActor
    func testTotalsSpeedSwapKeepsTextSizeAtLargeTextSize() {
        app.terminate()
        launch(textSize: "UICTContentSizeCategoryAccessibilityL")
        assertSpeedSwapKeepsTextSize()
    }

    @MainActor
    func testTotalsSessionsTapCyclesSetsAndLaps() {
        let sessions = total("logbook-total-sessions")
        XCTAssertTrue(sessions.waitForExistence(timeout: 30))
        app.scrollTo(sessions)
        XCTAssertTrue(sessions.label.contains("Sessions"), sessions.label)
        sessions.tap()
        XCTAssertTrue(sessions.label.contains("Sets"), sessions.label)
        sessions.tap()
        XCTAssertTrue(sessions.label.contains("Laps"), sessions.label)
        sessions.tap()
        XCTAssertTrue(sessions.label.contains("Sessions"), sessions.label)
    }

    @MainActor
    func testTotalsShowOneDecimal() {
        let distance = total("logbook-total-distance")
        XCTAssertTrue(distance.waitForExistence(timeout: 30))
        app.scrollTo(distance)
        let oneDecimal = NSPredicate(format: "label MATCHES %@", ".*[0-9][.,][0-9].*")
        XCTAssertTrue(oneDecimal.evaluate(with: distance), distance.label)
        distance.tap() // total time
        XCTAssertTrue(oneDecimal.evaluate(with: distance), distance.label)
        distance.tap() // riding time
        XCTAssertTrue(oneDecimal.evaluate(with: distance), distance.label)
    }
}
