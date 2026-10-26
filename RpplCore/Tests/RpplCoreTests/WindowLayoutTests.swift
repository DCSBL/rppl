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

    @Test("a compact width class stays a stack however wide the window is")
    func compactWidthClassStaysStack() {
        #expect(WindowLayout.resolve(width: 874, isAccessibilityTextSize: false, isCompactWidthClass: true) == .stack)
        #expect(WindowLayout.resolve(width: 874, isAccessibilityTextSize: false, isCompactWidthClass: false) == .twoPane)
    }

    @Test("the sidebar hosts the map only when collapsed, whatever the width")
    func sidebarHostsMapFollowsSizeClass() {
        #expect(WindowLayout.sidebarHostsMap(wantsMap: true, isCompactWidthClass: true))
        #expect(!WindowLayout.sidebarHostsMap(wantsMap: true, isCompactWidthClass: false))
        #expect(!WindowLayout.sidebarHostsMap(wantsMap: false, isCompactWidthClass: true))
    }
}
