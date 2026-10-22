import XCTest

/// Layout screenshots for iPhone Duo: Parks, the session list and a session's detail with the Duo closed,
/// half open and open. Until the Duo simulator is on the runners the three states are centered windows
/// (`-rpplUITestWindow WxH`) on an iPad, cropped to the window. Only runs when `RPPL_LAYOUT_SHOTS` is set
/// (`TEST_RUNNER_RPPL_LAYOUT_SHOTS=1`, see `.github/workflows/layouts.yml`), so the regular UI jobs skip it.
/// Text size comes from the simulator (`simctl ui content_size`). Names: `<screen>-<state>`.
final class RpplLayoutScreenshotTests: XCTestCase {
    /// Window sizes in points. shortcut: assumed, not Apple's Duo specs; adjust once the Duo simulator exists.
    private struct DuoState {
        let name: String
        let size: CGSize
    }

    private static let states = [
        DuoState(name: "closed", size: CGSize(width: 440, height: 956)),
        DuoState(name: "half-open", size: CGSize(width: 620, height: 956)),
        DuoState(name: "open", size: CGSize(width: 900, height: 956)),
    ]

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RPPL_LAYOUT_SHOTS"] != nil)
        continueAfterFailure = false
    }

    override func tearDown() {
        // Quit before the next test: terminating a still-running app at the next launch timed out once on CI.
        app?.terminate()
        super.tearDown()
    }

    private func launch(_ state: DuoState, _ args: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        let window = "\(Int(state.size.width))x\(Int(state.size.height))"
        app.launchArguments = ["-rpplUITest", "-rpplUITestWindow", window, "-AppleLanguages", "(en)", "-AppleLocale", "en_NL"] + args
        app.launch()
    }

    /// The screenshot cropped to the centered window, so the black margin of the iPad is not in the picture.
    private func shot(_ name: String, _ state: DuoState) {
        sleep(1)
        let screenshot = app.screenshot()
        let screen = app.windows.firstMatch.frame.size
        let scale = screenshot.image.size.width / max(screen.width, 1)
        let rect = CGRect(
            x: (screen.width - state.size.width) / 2 * scale,
            y: (screen.height - state.size.height) / 2 * scale,
            width: state.size.width * scale,
            height: state.size.height * scale
        )
        var image = screenshot.image
        if let cropped = image.cgImage?.cropping(to: rect) {
            image = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name)-\(state.name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func logbook(_ state: DuoState) {
        launch(state, ["-rpplUITestSessions", "18"])
        XCTAssertTrue(app.waitForSessionCount(18))
        shot("sessions", state)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wakeboard, Project 7")).firstMatch
        XCTAssertTrue(app.scrollToElement(card))
        card.tap()
        sleep(4) // detail and map tiles
        shot("session-detail", state)
    }

    private func parks(_ state: DuoState) {
        // Sat 5 Sep 14:00 Amsterdam: every mocked park is open.
        launch(state, ["-rpplUITestParkVisits", "-rpplUITestNow", "1788609600"])
        let tab = app.buttons["Parks"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.staticTexts["Parks"].waitForExistence(timeout: 15))
        shot("parks", state)
    }

    @MainActor func testLogbookClosed() { logbook(Self.states[0]) }
    @MainActor func testLogbookHalfOpen() { logbook(Self.states[1]) }
    @MainActor func testLogbookOpen() { logbook(Self.states[2]) }
    @MainActor func testParksClosed() { parks(Self.states[0]) }
    @MainActor func testParksHalfOpen() { parks(Self.states[1]) }
    @MainActor func testParksOpen() { parks(Self.states[2]) }
}
