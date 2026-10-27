import XCTest

/// Layout screenshots for wide and rotated windows (iPad, iPhone landscape, iPhone Duo): portrait and
/// landscape, Logbook with a session open and Parks. Only runs when `RPPL_LAYOUT_SHOTS` is set
/// (`TEST_RUNNER_RPPL_LAYOUT_SHOTS=1`, see `.github/workflows/ui-layout-screenshots.yml`), so the regular UI jobs skip it.
/// Text size comes from the simulator (`simctl ui content_size`). Names: `layout-<screen>-<orientation>`.
final class RpplLayoutScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RPPL_LAYOUT_SHOTS"] != nil)
        continueAfterFailure = false
        // Landscape at the largest text size, the list column shows about one card, so reaching one takes
        // many short drags: more than the job's two-minute default.
        executionTimeAllowance = 300
    }

    override func tearDown() {
        // Quit before the next test: terminating a still-running app at the next launch timed out once on CI.
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ orientation: UIDeviceOrientation, _ args: [String] = []) {
        XCUIDevice.shared.orientation = orientation
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"] + args
        app.launch()
    }

    private func shot(_ name: String, _ orientation: UIDeviceOrientation) {
        sleep(1)
        // The whole screen: app.screenshot() is cropped in landscape (XCTestCase+Screenshot.swift).
        attachScreenshot(named: "layout-\(name)-\(orientation.isLandscape ? "landscape" : "portrait")", of: app)
    }

    private func logbook(_ orientation: UIDeviceOrientation) {
        launch(orientation, ["-rpplUITestSessions", "18"])
        XCTAssertTrue(app.waitForSessionCount(18))
        shot("logbook", orientation)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wakeboard, Project 7")).firstMatch
        // Two-pane, the middle of the window is the detail column: drag the list itself.
        XCTAssertTrue(app.scrollToElement(card, in: app.collectionViews.firstMatch))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        sleep(4) // detail and map tiles
        shot("logbook-session", orientation)
    }

    private func parks(_ orientation: UIDeviceOrientation) {
        // Sat 5 Sep 14:00 Amsterdam: every mocked park is open.
        launch(orientation, ["-rpplUITestParkVisits", "-rpplUITestNow", "1788609600"])
        // The tab bar sits at the bottom on a phone and at the top on a wide window.
        let tab = app.buttons["Parks"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.staticTexts["Parks"].waitForExistence(timeout: 15))
        shot("parks", orientation)
    }

    @MainActor func testLogbookPortrait() { logbook(.portrait) }
    @MainActor func testLogbookLandscape() { logbook(.landscapeLeft) }
    @MainActor func testParksPortrait() { parks(.portrait) }
    @MainActor func testParksLandscape() { parks(.landscapeLeft) }
}
