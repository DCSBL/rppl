# Deep links

Custom scheme `rppl://`, registered in `Rppl/Info.plist` and `Info-Dev.plist` (`CFBundleURLTypes`). Works from widgets, Safari, Notes, Shortcuts ("Open URL") and NFC tags. Unknown or malformed links are ignored.

| Link | Opens | Parser (Core) |
|------|-------|---------------|
| `rppl://logbook` | Logbook tab | `TabDeepLink` |
| `rppl://session/<session-id>` | Session detail in the logbook | `SessionDeepLink` |
| `rppl://parks` | Parks tab | `TabDeepLink` |
| `rppl://parks/favorites` | Parks tab, nearby order, starred parks only | `ParkDeepLink.isFavorites` |
| `rppl://park/<park-id>` | Park detail | `ParkDeepLink` |
| `rppl://about` | Settings (about, iCloud), opens the Rppl modal | `TabDeepLink` |
| `rppl://debug` | Hidden Debug screen | `TabDeepLink` |

Examples:

```
rppl://session/6F1C0E5A-2B7D-4C3E-9A41-0D5E8B7C1F22
rppl://park/project7-rotterdam
rppl://parks/favorites
```

`<session-id>` is the session's `sessionId` (manifest). `<park-id>` is the park file's id (see [Parks.md](Parks.md)). An unknown id opens the tab and shows nothing selected.

## Where they are used

- Widgets: park hours (`rppl://park/<id>`), top parks (`rppl://parks/favorites`), last session (`rppl://session/<id>`).
- Debug screen (About, hold the logo): lists every link above; tap opens it, hold copies it.
- `rppl://add-reopening` is **internal**: the tappable day in the park detail "Opens again…" text, caught by an `OpenURLAction` in `ParkDetailView`. It never reaches `onOpenURL`.

## Adding a link

1. Parser and builder in `RpplCore` (pure, `TabDeepLink.swift` / `ParkWidget.swift`), with a test in `RpplCoreTests`.
2. Handle it in `ContentView.onOpenURL`.
3. Add a row to `DeepLinkCatalog.entries` (Debug screen; a test checks every entry is handled) and to the table above and in the README.

## Ideas, not built

- `rppl://session/<id>` from the Watch complication or a Live Activity.
- `rppl://add-session` to open the manual session editor (e.g. a Shortcut after a park day without Watch).
- `rppl://settings/icloud` straight to the iCloud Drive section.
- Universal links (`https://…`) would need a web domain with an apple-app-site-association file; out of scope while there is no Rppl server.
