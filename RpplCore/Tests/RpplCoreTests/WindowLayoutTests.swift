import Testing
@testable import RpplCore

@Suite("WindowLayout")
struct WindowLayoutTests {
    @Test(arguments: [
        (300.0, false, WindowLayout.stack),
        (519.9, false, .stack),
        (520.0, false, .twoPane),
        (800.0, false, .twoPane),
        (600.0, true, .stack),
        (759.9, true, .stack),
        (760.0, true, .twoPane),
    ])
    func resolvesByWidthAndTextSize(width: Double, accessibility: Bool, expected: WindowLayout) {
        #expect(WindowLayout.resolve(width: width, isAccessibilityTextSize: accessibility) == expected)
    }

    @Test func zeroWidthStacks() {
        #expect(WindowLayout.resolve(width: 0, isAccessibilityTextSize: false) == .stack)
    }
}
