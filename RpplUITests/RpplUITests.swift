import XCTest

/// Key iPhone flows against the seeded logbook (`UITestFixtures`: 1 tracked + 3 manual sessions,
/// clock frozen at Sat 15 Aug 2026 12:30). Queries use English labels.
final class RpplUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"]
        app.launch()
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
        XCTAssertTrue(card("Example session").waitForExistence(timeout: 30))
    }

    @MainActor
    func testLogbookListsSeededSessions() {
        XCTAssertTrue(card("Example session").waitForExistence(timeout: 30))
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
        XCTAssertTrue(app.staticTexts["5 total"].waitForExistence(timeout: 15))
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
}
