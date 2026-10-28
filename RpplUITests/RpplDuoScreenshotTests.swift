import XCTest

/// iPhone Duo release screenshots, on a wide iPhone as the stand-in until the Duo simulator is on the runners:
/// folded is the portrait window (one column), unfolded the landscape window (list left, detail right).
/// Only runs when `RPPL_DUO_SHOTS` is set (`TEST_RUNNER_RPPL_DUO_SHOTS=1`, see `.github/workflows/release-screenshots.yml`),
/// so the regular UI jobs skip it. Seeded mock logbook (`UITestFixtures`), clock frozen like `RpplScreenshotTests`.
/// CI exports the attachments and adds them to the release as `duo-<name>.png`.
final class RpplDuoScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RPPL_DUO_SHOTS"] != nil)
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    override func tearDown() {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ orientation: UIDeviceOrientation, _ args: [String]) {
        XCUIDevice.shared.orientation = orientation
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1) // let scroll/animation settle
        attachScreenshot(named: name, of: app) // the whole screen: app.screenshot() is cropped in landscape
    }

    /// Folded: the session list in one column.
    @MainActor
    func testFoldedLogbook() {
        launch(.portrait, ["-rpplUITestSessions", "3"])
        XCTAssertTrue(app.waitForSessionCount(3))
        shot("02-logbook-folded")
    }

    /// Unfolded: a tracked session open beside the list.
    @MainActor
    func testUnfoldedSessionDetail() {
        launch(.landscapeLeft, [])
        let tracked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wakeboard, Project 7 Cablepark")).firstMatch
        // Two panes: the middle of the window is the detail column, so drag the list itself.
        XCTAssertTrue(app.scrollToElement(tracked, in: app.collectionViews.firstMatch))
        // right edge: the card centre can land on a highlight chip
        tracked.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let loading = app.staticTexts["Loading GPS..."]
        _ = loading.waitForNonExistence(timeout: 30)
        sleep(4) // detail and map tiles
        shot("04-session-unfolded")
    }

    /// Unfolded: the parks that are open (Sat 5 Sep 2026 14:00 Amsterdam), list left, nothing selected.
    @MainActor
    func testUnfoldedParksOpen() {
        launch(.landscapeLeft, ["-rpplUITestParkVisits", "-rpplUITestNow", "1788609600"])
        let tab = app.buttons["Parks"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.staticTexts["Parks"].waitForExistence(timeout: 15))
        app.buttons["Most visited"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Project 7")).firstMatch.waitForExistence(timeout: 15))
        shot("06-parks-unfolded")
    }
}
