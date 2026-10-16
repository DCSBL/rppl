import XCTest

/// Release screenshots: seeded mock logbook, clock frozen at Sat 15 Aug 2026 12:30.
/// CI exports the attachments (`scripts/ci/export_screenshots.py`) and adds them to the release.
final class RpplScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"]
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1) // let scroll/animation settle
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func card(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    func testScreenshots() {
        XCTAssertTrue(card("Example session").waitForExistence(timeout: 30))
        shot("1-logbook")

        // right edge: the card centre can land on a highlight chip
        card("Example session").coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 30))
        sleep(2) // map tiles
        shot("2-session-detail")
        app.navigationBars.buttons.firstMatch.tap()

        card("Wakeboard, Lakeside Zwolle").tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
        shot("3-manual-session")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Parks"].tap()
        app.buttons["Search parks"].tap()
        app.textFields["Search parks"].typeText("Burnside\n") // return hides the keyboard
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() } // keyboard tip sheet
        shot("4-parks-list")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Burnside'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        sleep(1)
        shot("5-park-detail")
    }
}
