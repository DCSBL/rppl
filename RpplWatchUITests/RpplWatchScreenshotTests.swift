import XCTest

/// Watch screenshots and a UI sanity check: seeded logbook (`UITestFixtures` in RpplWatch, three
/// tracked Project 7 wakeboard sessions), clock frozen at Sat 15 Aug 2026 12:30. CI exports the
/// attachments (`scripts/ci/export_screenshots.py`); no live recording or HealthKit.
final class RpplWatchScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1) // let scroll/animation settle
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollShots(_ name: String, count: Int) {
        for i in 1...count {
            shot("\(name)-\(i)")
            if i < count { app.swipeUp() }
        }
    }

    private func openLogbook() {
        let logbook = app.buttons["Logbook"].firstMatch
        XCTAssertTrue(logbook.waitForExistence(timeout: 30))
        logbook.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Aug'")).firstMatch.waitForExistence(timeout: 30))
    }

    @MainActor
    func testStartPage() {
        launch()
        XCTAssertTrue(app.buttons["Logbook"].firstMatch.waitForExistence(timeout: 30))
        shot("01-start")
    }

    @MainActor
    func testSyncPage() {
        launch()
        let retry = app.buttons["Retry transfers"]
        var swipes = 0
        while !retry.waitForExistence(timeout: 2), swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(retry.exists)
        shot("02-sync")
    }

    @MainActor
    func testLogbookList() {
        launch()
        openLogbook()
        scrollShots("03-logbook", count: 3)
    }

    @MainActor
    func testSessionDetail() throws {
        try XCTSkip("Disabled: hangs the Watch simulator (github.com/DCSBL/rppl/issues/498)")
        launch()
        openLogbook()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Aug'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Duration"].firstMatch.waitForExistence(timeout: 30))
        sleep(3) // map snapshot
        scrollShots("04-session", count: 4)
    }

    @MainActor
    func testEndSummary() throws {
        try XCTSkip("Disabled: hangs the Watch simulator (github.com/DCSBL/rppl/issues/498)")
        launch(["-rpplUITestSummary"])
        XCTAssertTrue(app.staticTexts["SESSION COMPLETE"].waitForExistence(timeout: 30))
        sleep(3) // map snapshot
        scrollShots("05-summary", count: 2)
    }
}
