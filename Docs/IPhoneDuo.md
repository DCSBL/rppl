# iPhone Duo

Layout follows the window, not the device: `WindowLayout` (Core) picks one column or two panes from the width and the text size.

## Sidebar

The free strip beside the app is a trailing safe-area inset that the leading side does not have (`SidebarInset`, Core). When it exists, `ContentView` hides the tab bar and draws `DuoSidebar` in the strip:

- Top: the add button of the open tab, or back (a cross beside the Parks list) while a detail is open.
- Middle, bottom: the buttons of the open screen (share, favorite, edit, More).
- Bottom: Logbook and Parks, and the gear that opens the Rppl screen as a modal.

Screens put their buttons there with `.sidebarItems(...)`. Without a strip (other iPhones, iPad) the same buttons stay in the navigation bar, and the gear sits next to the add button in the Logbook and Parks headers.

## Divider on the fold

With a strip, the list column is half of the whole screen width (window plus strip), so the divider sits on the fold.

## Share

Share is one button. Where there are two destinations (a session with mail set up, a custom or edited park) it first asks "Share with Rppl?"; the other answer opens the share sheet.
