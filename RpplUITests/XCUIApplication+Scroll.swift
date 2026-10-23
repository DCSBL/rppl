import XCTest

extension XCUIApplication {
    /// Scrolls (short drags, so it cannot overshoot) until `element` is hittable in the upper part of the
    /// window. Lazy lists only build rows near the viewport (a small screen or big text pushes the cards
    /// off it), and a tap or swipe on a row at the screen edge misses. Stops once a drag no longer moves it.
    func scrollTo(_ element: XCUIElement, maxDrags: Int = 20) {
        let window = windows.firstMatch
        let height = window.frame.height
        func drag(up: Bool) {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.35))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        var previousMinY: CGFloat?
        for _ in 0..<maxDrags {
            guard element.exists else {
                drag(up: true)
                continue
            }
            let frame = element.frame
            if frame.maxY <= 0 {
                drag(up: false) // overshot: it is above the window
            } else if element.isHittable && frame.midY < height * 0.7 {
                return
            } else if frame.minY == previousMinY {
                return // the list cannot scroll further
            } else {
                previousMinY = frame.minY
                drag(up: true)
            }
        }
    }

    /// Scrolls to a session card or chart (rows are only built near the viewport). Waits on the tab bar, which
    /// stays on screen, and retries because the logbook may still be loading when the first swipes land.
    func scrollToElement(_ element: XCUIElement) -> Bool {
        guard tabBars.firstMatch.waitForExistence(timeout: 30) else { return false }
        for _ in 0..<3 {
            scrollTo(element)
            if element.waitForExistence(timeout: 10) { return true }
        }
        return false
    }

    /// Waits until the logbook totals tile reads `count` sessions. In a short, narrow list column (landscape at
    /// the largest text size) the header can push the tile off the viewport, so the list scrolls to it.
    func waitForSessionCount(_ count: Int, timeout: TimeInterval = 45) -> Bool {
        let tile = descendants(matching: .any)["logbook-total-sessions"].firstMatch
        let deadline = Date().addingTimeInterval(timeout) // one budget: the test allowance is 120 s in total
        if !tile.waitForExistence(timeout: 10) {
            let list = collectionViews.firstMatch
            for _ in 0..<4 where !tile.exists && list.exists {
                list.swipeUp()
            }
        }
        guard tile.waitForExistence(timeout: max(1, deadline.timeIntervalSinceNow)) else { return false }
        let reads = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", String(count)), object: tile)
        return XCTWaiter().wait(for: [reads], timeout: max(1, deadline.timeIntervalSinceNow)) == .completed
    }
}
