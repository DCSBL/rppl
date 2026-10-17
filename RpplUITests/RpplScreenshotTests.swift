import XCTest

/// Release screenshots: seeded mock logbook (`UITestFixtures`), clock frozen at Sat 15 Aug 2026 12:30.
/// CI exports the attachments (`scripts/ci/export_screenshots.py`) and adds them to the release.
/// Each test is one scenario and doubles as a UI check: it fails when a screen does not render.
final class RpplScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    /// Tue 17 Nov 2026 12:00 Amsterdam: seasonal parks are closed.
    private static let winterNow = "1794913200"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `args` are extra launch arguments, e.g. `["-rpplUITestSessions", "3"]`.
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

    /// Screenshots `name-1…name-n`, swiping up between them.
    private func scrollShots(_ name: String, count: Int) {
        for i in 1...count {
            shot("\(name)-\(i)")
            if i < count { app.swipeUp() }
        }
    }

    private func card(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func back() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: Logbook

    @MainActor
    func testLogbookEmpty() {
        launch(["-rpplUITestSessions", "0"])
        XCTAssertTrue(app.buttons["Add session"].waitForExistence(timeout: 30))
        shot("01-logbook-empty")
    }

    @MainActor
    func testLogbookThreeSessions() {
        launch(["-rpplUITestSessions", "3"])
        XCTAssertTrue(card("Wakeboard, Project 7 Cablepark").waitForExistence(timeout: 30))
        scrollShots("02-logbook-3", count: 2)
    }

    @MainActor
    func testLogbookEighteenSessions() {
        launch(["-rpplUITestSessions", "18"])
        XCTAssertTrue(app.descendants(matching: .any)["season-distance-chart"].firstMatch.waitForExistence(timeout: 60))
        scrollShots("03-logbook-18", count: 4)
    }

    // MARK: Session detail

    @MainActor
    func testTrackedSessionDetail() {
        launch()
        let tracked = card("Wakeboard, Project 7 Cablepark")
        XCTAssertTrue(app.scrollToCard(tracked))
        // right edge: the card centre can land on a highlight chip
        tracked.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 30))
        let loading = app.staticTexts["Loading GPS..."]
        _ = loading.waitForNonExistence(timeout: 30)
        sleep(3) // map tiles
        scrollShots("04-session-tracked", count: 5)
    }

    @MainActor
    func testManualSessionDetail() {
        launch()
        let manual = card("Wakeboard, Lakeside Zwolle")
        XCTAssertTrue(app.scrollToCard(manual))
        manual.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
        scrollShots("05-session-manual", count: 2)
    }

    // MARK: Parks

    private func openParks(args: [String] = []) {
        launch(args)
        XCTAssertTrue(app.tabBars.buttons["Parks"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Parks"].tap()
        // Nearby needs a location permission; the visit-sorted list works without one.
        app.buttons["Most visited"].tap()
        XCTAssertTrue(card("Project 7").waitForExistence(timeout: 15))
    }

    @MainActor
    func testParksOpen() {
        openParks()
        scrollShots("06-parks-open", count: 2)
    }

    @MainActor
    func testParksClosed() {
        openParks(args: ["-rpplUITestNow", Self.winterNow])
        scrollShots("07-parks-closed", count: 2)
    }

    @MainActor
    func testParksFavorites() {
        openParks(args: ["-rppl.favoriteParkIDs", "(project7-rotterdam, lakeside-zwolle, wakepark-groningen)"])
        shot("08-parks-starred")
        app.buttons["Favourites"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() // SwiftUI reports the pill as not hittable
        XCTAssertTrue(card("Project 7").waitForExistence(timeout: 15))
        shot("09-parks-favorites")
    }

    @MainActor
    func testParksMap() {
        openParks(args: ["-rppl.favoriteParkIDs", "(project7-rotterdam, lakeside-zwolle)"])
        app.buttons["View on map"].tap()
        sleep(4) // map tiles
        shot("10-parks-map")
        app.buttons["Show satellite map"].tap()
        sleep(4)
        shot("11-parks-satellite")
    }

    @MainActor
    func testParkDetail() {
        openParks()
        card("Project 7").tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
        scrollShots("12-park-detail", count: 3)
    }
}
