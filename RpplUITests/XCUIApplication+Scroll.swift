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

    /// Scrolls to a session card (rows are only built near the viewport). Waits on the tab bar, which
    /// stays on screen, and retries because the logbook may still be loading when the first swipes land.
    func scrollToCard(_ card: XCUIElement) -> Bool {
        guard tabBars.firstMatch.waitForExistence(timeout: 30) else { return false }
        for _ in 0..<3 {
            scrollTo(card)
            if card.waitForExistence(timeout: 10) { return true }
        }
        return false
    }
}
