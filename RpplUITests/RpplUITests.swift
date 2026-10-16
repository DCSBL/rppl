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

    /// Scrolls the logbook up until the element is on screen (charts sit below the totals).
    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }

    private func card(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    func testTabsSwitch() {
        XCTAssertTrue(app.staticTexts["Logbook"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Parks"].tap()
        XCTAssertTrue(app.staticTexts["Parks"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Rppl"].tap()
        XCTAssertTrue(app.tabBars.buttons["Rppl"].isSelected)
        app.tabBars.buttons["Logbook"].tap()
        XCTAssertTrue(card("Wakeboard, Project 7 Cablepark").waitForExistence(timeout: 30))
    }

    @MainActor
    func testLogbookListsSeededSessions() {
        XCTAssertTrue(card("Wakeboard, Project 7 Cablepark").waitForExistence(timeout: 30))
        XCTAssertTrue(card("Wakeboard, Lakeside Zwolle").exists)
        XCTAssertTrue(card("Wakeboard, Wakepark Groningen").exists)
        XCTAssertTrue(app.staticTexts["4 total"].exists)
    }

    @MainActor
    func testOpenSessionDetailAndBack() {
        let zwolle = card("Wakeboard, Lakeside Zwolle")
        XCTAssertTrue(zwolle.waitForExistence(timeout: 30))
        zwolle.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Zwolle'")).firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(zwolle.waitForExistence(timeout: 15))
    }

    @MainActor
    func testDeleteSessionBySwipe() {
        let groningen = card("Wakeboard, Lakeside Zwolle")
        XCTAssertTrue(groningen.waitForExistence(timeout: 30))
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
        XCTAssertTrue(app.staticTexts["5, Sessions"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.staticTexts["3 total"].waitForExistence(timeout: 30))
        XCTAssertFalse(chart("season-distance-chart").exists)
        XCTAssertFalse(chart("season-temperature-chart").exists)
    }

    @MainActor
    func testSeasonChartsShownWithEighteenSessions() {
        app.terminate()
        launch(sessions: 18)
        // The "18 total" header sits below the charts, so the lazy list never builds it on screen.
        let distance = chart("season-distance-chart")
        XCTAssertTrue(distance.waitForExistence(timeout: 60))
        XCTAssertEqual(distance.value as? String, "18") // one bar per session
        XCTAssertGreaterThan(distance.frame.height, 50)

        app.buttons["Duration"].tap()
        XCTAssertEqual(chart("season-duration-chart").value as? String, "18")

        let temperature = chart("season-temperature-chart")
        scrollTo(temperature)
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
        XCTAssertEqual(total("logbook-total-speed").frame.height, sessions.frame.height, accuracy: 0.5)
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
        let oneDecimal = NSPredicate(format: "label MATCHES %@", ".*[0-9][.,][0-9].*")
        XCTAssertTrue(oneDecimal.evaluate(with: distance), distance.label)
        distance.tap() // total time
        XCTAssertTrue(oneDecimal.evaluate(with: distance), distance.label)
        distance.tap() // riding time
        XCTAssertTrue(oneDecimal.evaluate(with: distance), distance.label)
    }
}
