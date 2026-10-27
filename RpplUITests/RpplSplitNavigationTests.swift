import XCTest

/// Opening, switching and closing a park or session in the Parks and Logbook split views, the flows that
/// broke on iPhone Duo. On iPad (`ui-split-navigation.yml`) the list and the detail stand side by side, as
/// on an unfolded Duo; on iPhone (the regular UI job) the split view is collapsed, as on a folded Duo.
/// The detail is checked by its texts: list cards are one combined element, so their texts do not show up
/// as `staticTexts`.
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

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
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
            XCTAssertFalse(bars.isEmpty, "no navigation bar")
            bars.last?.buttons.firstMatch.tap()
        }
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    // MARK: Logbook

    private func openSession(_ park: String) {
        let card = card("Wakeboard, \(park)")
        XCTAssertTrue(app.scrollToElement(card, in: isPad ? app.collectionViews.firstMatch : nil), "no card for \(park)")
        // Beside the detail, tap the card's trailing edge: its middle may hold a link.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    @MainActor
    func testSessionOpensAndBackReturns() {
        launch()
        openSession("Lakeside Zwolle")
        XCTAssertTrue(text(containing: "Zwolle").waitForExistence(timeout: 15), "session detail did not open")
        tapBack()
        XCTAssertTrue(waitGone(text(containing: "Zwolle")), "back did not close the session")
        // The same session again: a selection left behind after back made this tap a no-op.
        openSession("Lakeside Zwolle")
        XCTAssertTrue(text(containing: "Zwolle").waitForExistence(timeout: 15), "session did not open a second time")
    }

    @MainActor
    func testPickingAnotherSessionReplacesTheOpenOne() throws {
        try XCTSkipUnless(isPad, "needs the list beside the detail (iPad)")
        launch()
        openSession("Lakeside Zwolle")
        XCTAssertTrue(text(containing: "Zwolle").waitForExistence(timeout: 15), "first session did not open")
        openSession("Wakepark Groningen")
        XCTAssertTrue(text(containing: "Groningen").waitForExistence(timeout: 15), "second session did not open")
        XCTAssertTrue(waitGone(text(containing: "Zwolle")), "first session still shown")
        tapBack()
        XCTAssertTrue(app.staticTexts["No session selected"].waitForExistence(timeout: 15), "back did not return to the placeholder")
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
        if app.buttons["Close search"].exists { app.buttons["Close search"].tap() }
        app.buttons["Search parks"].firstMatch.tap()
        let field = app.textFields["Search parks"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", query)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "no park found for \(query)")
        result.tap()
    }

    @MainActor
    func testParkOpensAndBackReturns() {
        launch()
        openParksTab()
        openPark("Zwolle")
        XCTAssertTrue(text(containing: "Zwolle").waitForExistence(timeout: 15), "park detail did not open")
        tapBack()
        XCTAssertTrue(waitGone(text(containing: "Zwolle")), "back did not close the park")
        openPark("Zwolle")
        XCTAssertTrue(text(containing: "Zwolle").waitForExistence(timeout: 15), "park did not open a second time")
    }

    @MainActor
    func testPickingAnotherParkReplacesTheOpenOne() throws {
        try XCTSkipUnless(isPad, "needs the list beside the detail (iPad)")
        launch()
        openParksTab()
        openPark("Zwolle")
        XCTAssertTrue(text(containing: "Zwolle").waitForExistence(timeout: 15), "first park did not open")
        openPark("Groningen")
        XCTAssertTrue(text(containing: "Groningen").waitForExistence(timeout: 15), "second park did not open")
        XCTAssertTrue(waitGone(text(containing: "Zwolle")), "first park still shown")
        tapBack()
        XCTAssertTrue(waitGone(text(containing: "Groningen")), "back did not close the park")
    }
}
