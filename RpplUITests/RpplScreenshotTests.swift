import XCTest

/// Release screenshots: seeded mock logbook (`UITestFixtures`), clock frozen at Sat 15 Aug 2026 12:30 (Parks: Sat 5 Sep 14:00).
/// CI exports the attachments (`scripts/ci/export_screenshots.py`) and adds them to the release.
/// Each test is one scenario and doubles as a UI check: it fails when a screen does not render.
/// `RpplDarkScreenshotTests` re-runs every scenario in dark mode (`<name>-dark.png`).
/// The generated logbooks (`-rpplUITestSessions N`) mix tracked and manual sessions.
class RpplScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    /// Overridden by the dark-mode subclass.
    class var isDark: Bool { false }

    /// Sat 5 Sep 2026 14:00 Amsterdam: every mocked park is within its opening hours.
    private static let summerNow = "1788609600"

    /// Tue 17 Nov 2026 12:00 Amsterdam: seasonal parks are closed.
    private static let winterNow = "1794913200"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `args` are extra launch arguments, e.g. `["-rpplUITestSessions", "3"]`.
    private func launch(_ args: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"] + args
        if Self.isDark { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1) // let scroll/animation settle
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = Self.isDark ? "\(name)-dark" : name
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
        XCTAssertTrue(app.waitForSessionCount(3))
        scrollShots("02-logbook-3", count: 2)
    }

    @MainActor
    func testLogbookEighteenSessions() {
        launch(["-rpplUITestSessions", "18"])
        XCTAssertTrue(app.waitForSessionCount(18))
        scrollShots("03-logbook-18", count: 4)
    }

    // MARK: Session detail

    @MainActor
    func testTrackedSessionDetail() {
        launch()
        let tracked = card("Wakeboard, Project 7 Cablepark")
        XCTAssertTrue(app.scrollToElement(tracked))
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
        XCTAssertTrue(app.scrollToElement(manual))
        manual.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15))
        scrollShots("05-session-manual", count: 2)
    }

    // MARK: Parks

    private func openParks(args: [String] = []) {
        // Visit counts mocked so Project 7, Wet 'n Wild, Wollebrand and Down Under lead the list.
        launch(["-rpplUITestParkVisits"] + (args.contains("-rpplUITestNow") ? [] : ["-rpplUITestNow", Self.summerNow]) + args)
        XCTAssertTrue(app.tabBars.buttons["Parks"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Parks"].tap()
        // Nearby needs a location permission; the visit-sorted list works without one.
        app.buttons["Most visited"].tap()
        let found = card("Project 7").waitForExistence(timeout: 15)
        if !found { print("PARKS-DIAG-BEGIN\n\(app.debugDescription)\nPARKS-DIAG-END") }
        XCTAssertTrue(found)
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

final class RpplDarkScreenshotTests: RpplScreenshotTests {
    override class var isDark: Bool { true }
}
