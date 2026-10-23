# iPhone Duo

Layout follows the window, not the device: `WindowLayout` (Core) picks one column or two panes from the width and the text size.

## The strip beside the app

Build with the iOS 27.1 SDK (Xcode 27.1, also in Xcode Cloud). Then the app runs edge to edge and the system lays standard navigation bars, toolbars and tab bars out vertically under the status bar. An iOS 27 build stops left of the status bar and the strip stays black; there is nothing to draw in it. So the app uses plain `TabView` and `.toolbar` items and has no sidebar of its own (an earlier custom sidebar, based on a trailing safe-area inset, never triggered on a real Duo and was removed).

Logbook and Parks use the navigation bar's own large title and put their buttons in it: search (Parks), settings (the gear, opens the Rppl screen as a modal), then add. In a split view the system picks the column widths, and on iPhone Duo puts the divider on the fold; Rppl sets no widths of its own.

Detail screens give the trailing side a smaller margin when the vertical bar is there (`detailMargins`): the bar already keeps the cards clear of the edge.

## Full-screen maps

Tapping a map preview (a session, a set, a park) pushes a full-screen map: over the whole window when folded, in the detail column beside a list. The Parks map ("View on map", and the map beside the list) works the same way. Every one of them has the same buttons in the navigation bar (`MapScreenToolbar`): back, map style (a globe on the map, a map on satellite), then here (parks) or reset to the fitted frame (sessions and sets), then the compass. There is no 3D button; tilting stays a two-finger gesture.

## Share

Share is one button. Where there are two destinations (a session with mail set up, a custom or edited park) it first asks "Share with Rppl?"; the other answer opens the share sheet.
