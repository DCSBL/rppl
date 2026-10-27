import XCTest

/// Opening, switching and closing a park or session in the Parks and Logbook split views, the flows that
/// broke on iPhone Duo. On iPad (`ui-split-navigation.yml`) the test makes the app's window full screen, so the
/// list shows beside the detail as on an unfolded Duo; on iPhone (the regular UI job) the split view is
/// collapsed, as on a folded Duo. Portrait on purpose: in landscape the CI iPad gave the app a 476pt window.
/// The detail is found by its accessibility identifier (`park-detail-<id>`, `session-detail-<park id>`). On a
/// failed check the test prints the accessibility tree to the log, so a CI run shows what was on screen.
final class RpplSplitNavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-rpplUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"]
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    /// Whether the list shows beside the detail, read from the screen: the Logbook's empty detail
    /// placeholder only shows when the split view is not collapsed. Not the window width: iPadOS opens the
    /// app in a window (635pt on CI) whose size class is compact, and then it behaves like a folded Duo.
    private var isTwoPane = false

    private var windowWidth: Int { Int(app.windows.firstMatch.frame.width) }

    private func launch() {
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "the app did not start")
        isTwoPane = app.staticTexts["No session selected"].waitForExistence(timeout: 5)
        if !isTwoPane, UIDevice.current.userInterfaceIdiom == .pad {
            enterFullScreen()
            isTwoPane = app.staticTexts["No session selected"].waitForExistence(timeout: 5)
        }
        print("window: \(windowWidth)pt wide, two panes: \(isTwoPane)")
    }

    /// iPadOS opens apps in a resizable window. Its window controls (SpringBoard's) offer Zoom, which fills the
    /// screen; otherwise drag the window's resize grabber to the bottom right corner of the screen.
    private func enterFullScreen() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let controls = springboard.buttons["window-controls:nl.dcsbl.rppl"]
        if controls.waitForExistence(timeout: 3) {
            controls.tap()
            let fill = springboard.descendants(matching: .any).matching(NSPredicate(
                format: "label == 'Zoom' OR label BEGINSWITH[c] 'Fill' OR label CONTAINS[c] 'Full Screen'"
            )).firstMatch
            if fill.waitForExistence(timeout: 3) {
                print("window controls: tapping '\(fill.label)'")
                fill.tap()
                return
            }
            let items = springboard.descendants(matching: .any).allElementsBoundByIndex
                .map(\.label).filter { !$0.isEmpty }
            print("window controls offer no fill: \(items.joined(separator: ", "))")
            if controls.exists { controls.tap() }
        }
        let grabber = springboard.descendants(matching: .any)["resize-grabber"]
        guard grabber.waitForExistence(timeout: 3) else {
            print("no resize grabber")
            return
        }
        let corner = springboard.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5, thenDragTo: corner)
        print("dragged the resize grabber; window now \(windowWidth)pt wide")
    }

    /// Guards the side-by-side tests below from skipping unnoticed: on an iPad the list should show beside
    /// the detail, and if CI hands the app a compact window, those tests are not covering anything.
    @MainActor
    func testIPadWindowIsWideEnoughForTwoPanes() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        launch()
        check(isTwoPane, "the iPad window is \(windowWidth)pt wide and the split view collapses")
    }

    /// Skips a side-by-side test when the split view is collapsed, naming the window width.
    private func requireTwoPane() throws {
        try XCTSkipUnless(isTwoPane, "needs the list beside the detail; this window is \(windowWidth)pt wide and collapsed")
    }

    private func parkDetail(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["park-detail-\(id)"].firstMatch
    }

    private func sessionDetail(_ parkID: String) -> XCUIElement {
        app.descendants(matching: .any)["session-detail-\(parkID)"].firstMatch
    }

    /// Fails with the accessibility tree in the log.
    private func check(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard !condition else { return }
        print("--- accessibility tree at failure: \(message) ---\n\(app.debugDescription)")
        XCTFail(message, file: file, line: line)
    }

    private func waitShown(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    private func card(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The navigation bar that shows a back button: the detail's, not the list column's.
    private func tapBack() {
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Back' OR identifier == 'BackButton'")).firstMatch
        if back.waitForExistence(timeout: 5) {
            back.tap()
        } else {
            // The system back button carries the previous title as its label; the detail bar is the last one.
            let bars = app.navigationBars.allElementsBoundByIndex
            check(!bars.isEmpty, "no navigation bar")
            bars.last?.buttons.firstMatch.tap()
        }
    }

    /// The split view may hide the list while a pushed detail is open; the sidebar button brings it back.
    /// `marker` is an element of the list.
    private func revealList(_ marker: XCUIElement) {
        guard isTwoPane, !marker.waitForExistence(timeout: 2) else { return }
        let toggle = app.buttons.matching(NSPredicate(
            format: "identifier == 'ToggleSidebar' OR label == 'Show Sidebar' OR label == 'Sidebar' OR label == 'Show sidebar'"
        )).firstMatch
        check(toggle.waitForExistence(timeout: 5), "list hidden and no sidebar button")
        toggle.tap()
        check(marker.waitForExistence(timeout: 10), "list did not come back")
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    // MARK: Logbook

    private func openSession(_ park: String) {
        let card = card("Wakeboard, \(park)")
        revealList(app.collectionViews.firstMatch)
        check(app.scrollToElement(card, in: isTwoPane ? app.collectionViews.firstMatch : nil), "no card for \(park)")
        // Beside the detail, tap the card's trailing edge: its middle may hold a link.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    @MainActor
    func testSessionOpensAndBackReturns() {
        launch()
        openSession("Lakeside Zwolle")
        check(waitShown(sessionDetail("lakeside-zwolle")), "session detail did not open")
        tapBack()
        check(waitGone(sessionDetail("lakeside-zwolle")), "back did not close the session")
        // The same session again: a selection left behind after back made this tap a no-op.
        openSession("Lakeside Zwolle")
        check(waitShown(sessionDetail("lakeside-zwolle")), "session did not open a second time")
    }

    @MainActor
    func testPickingAnotherSessionReplacesTheOpenOne() throws {
        launch()
        try requireTwoPane()
        openSession("Lakeside Zwolle")
        check(waitShown(sessionDetail("lakeside-zwolle")), "first session did not open")
        openSession("Wakepark Groningen")
        check(waitShown(sessionDetail("wakepark-groningen")), "second session did not open")
        check(waitGone(sessionDetail("lakeside-zwolle")), "first session still shown")
        tapBack()
        check(waitShown(app.staticTexts["No session selected"]), "back did not return to the placeholder")
    }

    // MARK: Parks

    private func openParksTab() {
        let tab = app.buttons["Parks"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.staticTexts["Parks"].waitForExistence(timeout: 15))
    }

    /// Finds the park with the list's search and taps its card.
    private func openPark(_ query: String) {
        revealList(app.buttons.matching(NSPredicate(format: "label == 'Search parks' OR label == 'Close search'")).firstMatch)
        if app.buttons["Close search"].exists { app.buttons["Close search"].tap() }
        app.buttons["Search parks"].firstMatch.tap()
        let field = app.textFields["Search parks"]
        check(field.waitForExistence(timeout: 15), "no search field")
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", query)).firstMatch
        check(result.waitForExistence(timeout: 15), "no park found for \(query)")
        result.tap()
    }

    @MainActor
    func testParkOpensAndBackReturns() {
        launch()
        openParksTab()
        openPark("Zwolle")
        check(waitShown(parkDetail("lakeside-zwolle")), "park detail did not open")
        tapBack()
        check(waitGone(parkDetail("lakeside-zwolle")), "back did not close the park")
        openPark("Zwolle")
        check(waitShown(parkDetail("lakeside-zwolle")), "park did not open a second time")
    }

    @MainActor
    func testPickingAnotherParkReplacesTheOpenOne() throws {
        launch()
        try requireTwoPane()
        openParksTab()
        openPark("Zwolle")
        check(waitShown(parkDetail("lakeside-zwolle")), "first park did not open")
        openPark("Groningen")
        check(waitShown(parkDetail("wakepark-groningen")), "second park did not open")
        check(waitGone(parkDetail("lakeside-zwolle")), "first park still shown")
        tapBack()
        check(waitGone(parkDetail("wakepark-groningen")), "back did not close the park")
    }
}
