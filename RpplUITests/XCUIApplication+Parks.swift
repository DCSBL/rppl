import XCTest

extension XCUIApplication {
    /// Whether the Parks header uses the accessibility layout: the sort segments and filter pills are then
    /// "Sort" and "Filters" bar menus. Decided once the header is on screen.
    private var usesParksMenus: Bool { buttons["Sort"].exists }

    /// Waits for the Parks header, whichever layout it has.
    private func waitForParksHeader(_ segment: XCUIElement) {
        let deadline = Date().addingTimeInterval(15)
        while !segment.exists, !usesParksMenus, Date() < deadline {
            usleep(200_000)
        }
    }

    /// Picks "Nearby", "Most visited" or "View on map": a segment normally, a "Sort" menu item at
    /// accessibility text sizes.
    func chooseParksSort(_ option: String) {
        let segment = segmentedControls.buttons[option]
        waitForParksHeader(segment)
        if usesParksMenus {
            buttons["Sort"].tap()
            let item = buttons[option]
            XCTAssertTrue(item.waitForExistence(timeout: 10), "sort menu item \(option)")
            item.tap()
        } else {
            segment.tap()
        }
    }

    /// Whether a sort option is offered; opens and closes the "Sort" menu at accessibility text sizes.
    func parksSortOptionExists(_ option: String) -> Bool {
        let segment = segmentedControls.buttons[option]
        waitForParksHeader(segment)
        guard usesParksMenus else { return segment.waitForExistence(timeout: 15) }
        buttons["Sort"].tap()
        let exists = buttons[option].waitForExistence(timeout: 10)
        // A tap outside closes the menu without choosing.
        windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        return exists
    }

    /// Turns a filter such as "Favourites" on: a pill normally, a "Filters" menu item at accessibility
    /// text sizes.
    func toggleParksFilter(_ option: String) {
        let pill = buttons[option]
        waitForParksHeader(pill)
        if usesParksMenus {
            buttons["Filters"].tap()
            let item = buttons[option]
            XCTAssertTrue(item.waitForExistence(timeout: 10), "filter menu item \(option)")
            item.tap()
        } else {
            pill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() // SwiftUI reports the pill as not hittable
        }
    }
}
