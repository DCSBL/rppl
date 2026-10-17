import XCTest

extension XCUIApplication {
    /// Swipes up until `element` is hittable and in the upper part of the window. Lazy lists only build
    /// rows near the viewport (a small screen or big text pushes the cards off it), and a swipe on a row
    /// at the screen edge misses. Stops early once a swipe no longer moves the element.
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) {
        let height = windows.firstMatch.frame.height
        var previousMinY: CGFloat?
        for _ in 0..<maxSwipes {
            if element.isHittable {
                if element.frame.midY < height * 0.7 || element.frame.minY == previousMinY { return }
                previousMinY = element.frame.minY
            }
            swipeUp()
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
