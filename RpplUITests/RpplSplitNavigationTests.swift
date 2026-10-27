import XCTest

/// Opening, switching and closing a park or session in the Parks and Logbook split views, the flows that
/// broke on iPhone Duo. On iPad (`ui-split-navigation.yml`) the list and the detail stand side by side, as
/// on an unfolded Duo; on iPhone (the regular UI job) the split view is collapsed, as on a folded Duo.
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
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func launch() {
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launch()
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

    /// On iPad the split view hides the list while a pushed detail is open (too little room for both next to
    /// the tab bar's split); the sidebar button brings it back. A Duo keeps both side by side. `marker` is an
    /// element of the list.
    private func revealList(_ marker: XCUIElement) {
        guard isPad, !marker.waitForExistence(timeout: 2) else { return }
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
        check(app.scrollToElement(card, in: isPad ? app.collectionViews.firstMatch : nil), "no card for \(park)")
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
        try XCTSkipUnless(isPad, "needs the list beside the detail (iPad)")
        launch()
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
        try XCTSkipUnless(isPad, "needs the list beside the detail (iPad)")
        launch()
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
