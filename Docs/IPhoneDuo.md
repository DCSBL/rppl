# iPhone Duo

Layout follows the window, not the device: `WindowLayout` (Core) picks one column or two panes from the width and the text size.

## The strip beside the app

Build with the iOS 27.1 SDK (Xcode 27.1, also in Xcode Cloud). Then the app runs edge to edge and the system lays standard navigation bars, toolbars and tab bars out vertically under the status bar. An iOS 27 build stops left of the status bar and the strip stays black; there is nothing to draw in it. So the app uses plain `TabView` and `.toolbar` items and has no sidebar of its own (an earlier custom sidebar, based on a trailing safe-area inset, never triggered on a real Duo and was removed).

The gear that opens the Rppl screen as a modal sits next to the add button in the Logbook and Parks headers.

## Share

Share is one button. Where there are two destinations (a session with mail set up, a custom or edited park) it first asks "Share with Rppl?"; the other answer opens the share sheet.
