# HIG UI / interaction backlog

Apple HIG audit notes for Rppl Watch + iPhone (UI and interaction only).
App icons / marketing assets stay out of scope.

Sibling PRs in the first pass shipped clear interaction fixes. Follow-ups tracked in Linear [DCSBL-51](https://linear.app/dcsbl/issue/DCSBL-51/hig-ui-follow-ups-pr-48).

Housekeeping: example session CTA [DCSBL-48](https://linear.app/dcsbl/issue/DCSBL-48) Done; left-float tab bar [DCSBL-23](https://linear.app/dcsbl/issue/DCSBL-23) Canceled (#61).

## Shipped in first pass (sibling PRs)

| Fix | PR | Why (HIG) |
|-----|----|-----------|
| HIG backlog (this doc) | #48 | Track deferred decisions |
| Watch Stop confirmation | #49 | Workouts / Feedback — confirm irreversible end |
| Phone export + delete failure alerts | #50 | Feedback — surface failed actions |
| Phone Logbook sync status | #51 | Feedback — companion connection in-context |
| Resume on paused metrics page | #52 | Gestures — visible control, not swipe-only |
| Start / Stop / Pause haptics | #53 | Playing haptics — Start/Stop for explicit control |
| MDI + control VoiceOver labels; idle sync stays tappable while starting | #54 | Accessibility |
| Ride timer Dynamic Type (drop fixed pt) | #55 | Typography / Accessibility |
| Watch sync-complete notification + background re-queue | #56 | Feedback / WC background |
| Defer Watch permission sheets until start | #57 | Onboarding — request in context |
| iPhone “Watch required” / how-to-start copy | #58 | Onboarding / Feedback |
| Watch permissions onboarding checklist | #59 | Onboarding |
| iPhone About permissions list; ask after first sync | #60 | Onboarding / Feedback |
| Drop TabBarLeadingAligner (Liquid Glass) | #61 | WWDC25-356 — no private platter pin |

Graphite stack unavailable — these are independent PRs off `main` (except #60 stacks on #59). `#52`, `#54`, and `#55` all touch `SessionRideUIPage.swift` (expect small conflicts).

## Onboarding (product lock + HIG)

Previously skipped here; now tracked. Full first-run flow still a later build — keep Logbook example + Watch-first recording.

### HIG principles that apply

- **[Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding):** Keep first launch short. Prefer value in the product surface over a long carousel. Explain *why* before requesting access. Request permissions **in context** (when the feature runs), not stacked at cold launch.
- **[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback):** Empty and companion states should say what to do next (start on Watch, pair, install Watch app).
- **[Modality](https://developer.apple.com/design/human-interface-guidelines/modality):** Avoid blocking sheets for education the user can skip; prefer in-place empty copy + optional example.
- **[Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos):** Watch app must work alone for recording; phone is the companion for review/export. Don’t imply phone-only recording.
- **App Store listing** (product, not HIG UI): state Apple Watch required for recording; iPhone alone cannot capture sessions.

### Product notes (Duco)

**Keep**

- Example session on empty Logbook — explore maps/stats **before** first real workout.
- No forced multi-page onboarding carousel for alpha.

**Fix**

- iPhone must make **Apple Watch required** and **how to start** obvious in-app (empty Logbook + About). Non–Apple Watch users cannot record; say so clearly (App Store copy too).
- Watch must **not** fire Health/location permission sheets on first app open. Request when starting a session (and Idle Sync “Permissions”), not `ContentView.onAppear`.

### Implementation status

| Item | Status |
|------|--------|
| Keep example session CTA | Shipped (empty Logbook) |
| Stronger “Watch required / start on Watch” iPhone copy | #58 |
| Defer Watch permission prompts off cold launch | #57 |
| Watch permissions onboarding checklist | #59 |
| iPhone About permissions list; ask after first sync | #60 |
| Multi-step branded onboarding | Deferred (alpha) |

## Sync: background WC + completion notice

Watch→phone session packages already use **`WCSession.transferFile`** (system queue). Phone acks with **`transferUserInfo`** (+ optional live `sendMessage`). **Neither app needs to stay foreground** for queued delivery; system wakes briefly for delegates when radio allows.

| Item | Status |
|------|--------|
| Background-capable transfer APIs | Already in code |
| Re-queue pending on Watch become-active / scene active | #56 |
| Local notification on Watch when phone **acks** (sync complete) | #56 |
| Notification auth in context (at transfer / stop), not cold launch | #56 |
| Skip duplicate outstanding WC file transfers | #56 |

Caveats: delivery can stall until Watch↔iPhone connect; phone unlocked may suppress Watch banners (system). Keep data until ack (hard constraint).

## Open follow-ups ([DCSBL-51](https://linear.app/dcsbl/issue/DCSBL-51/hig-ui-follow-ups-pr-48))

### Watch: session end summary (High)

**Shipped** (session-end summary after Stop).



### iPhone: Logbook card crowding at large Dynamic Type (High)

[`SessionCard`](../Rppl/Logbook/LogbookView.swift) packs four caption stats in one `HStack`; Totals uses a three-metric strip.

**Locked:** At accessibility sizes, switch stats to **2×2 grid**; Totals strip stacks vertically.

**Status:** Shipped #80 — `dynamicTypeSize.isAccessibilitySize` layout branch in Logbook.

### Watch: tiny-session discard / cancel (Medium)

**Shipped.** If duration < ~30s **and** zero rides, Stop offers Discard / Keep / Cancel. Discard deletes local package (no transfer, no Health save). Keep uses normal stop + transfer; keep-until-phone-ack unchanged. Never silent-delete.

**Touches:** `TinySessionPolicy` (Core), `SessionControlsPage`, `discardSession` / `discardWorkoutWithoutSaving`.

### Logbook concentric corner radii (Low)

**Locked:** Audit nested shapes (icon well inside card); fix radii for Liquid Glass.

**Shipped:** Logbook cards use `containerShape` + nested `.rect(corners: .concentric…)` (session/ride cards, stat tiles, ride maps). Session-card icon well dropped earlier (#76); nest still applies to detail tiles/maps. See [`LogbookLayout.swift`](../Rppl/Logbook/LogbookLayout.swift).

### Shipped / dropped

| Item | Status |
|------|--------|
| Watch session-end summary | Shipped |
| Watch tiny-session discard | Shipped (DCSBL-51 Medium) |
| Watch Always On / reduced luminance | Shipped — `isLuminanceReduced` dims secondary chrome; primary metric full; controls stay (Ride + Controls pages) |
| Watch idle brand colors vs system appearance | Shipped [DCSBL-52](https://linear.app/dcsbl/issue/DCSBL-52/watch-idle-brand-colors-vs-system-appearance) |
| `TabBarLeadingAligner` private platter pin | Shipped #61; [DCSBL-23](https://linear.app/dcsbl/issue/DCSBL-23) Canceled |
| Soften About `toolbarBackground` | Dropped (alpha polish) |
| Logbook concentric corner radii | Shipped (this PR); [DCSBL-51](https://linear.app/dcsbl/issue/DCSBL-51/hig-ui-follow-ups-pr-48) |

## Liquid Glass / WWDC25-356 notes

Source: [Get to know the new design system (WWDC25-356)](https://developer.apple.com/videos/play/wwdc2025/356/). Companion: Meet Liquid Glass.

Not about WC/HealthKit — still shapes how Rppl should sit on iOS 26 / watchOS 26.

| Takeaway | Rppl action |
|----------|-------------|
| Strip custom bar backgrounds / borders; hierarchy from layout + grouping | Drop `TabBarLeadingAligner`; avoid fighting floating tab platter |
| Content first; chrome floats above without stealing focus | Keep Logbook maps/sessions as content; light sync chrome; prefer scroll edge effects over hard dividers |
| Concentric corner radii for nested shapes | Shipped — Logbook cards `containerShape` + nested concentric rects |
| Shared anatomy across devices; same symbols | Keep mirrored Location/Health/Motion lists + SF Symbols on Watch + iPhone |
| Bolder left-aligned type in alerts / onboarding | Stick to system `List` + semantic text on permission gates |
| Toolbar: group by function; primary separate/tinted | Export/Share stay system; soften forced `toolbarBackground` on About |
| Dedicated Search tab pattern (later) | If Logbook search lands, prefer system Search tab over stuffing nav |

### Still open after 356

- Soften About nav bar background — dropped (alpha polish)

## Reference links

- [Get to know the new design system (WWDC25-356)](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Workouts](https://developer.apple.com/design/human-interface-guidelines/workouts)
- [Always On](https://developer.apple.com/design/human-interface-guidelines/always-on)
- [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Modality](https://developer.apple.com/design/human-interface-guidelines/modality)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)

## Explicitly out of scope here

- Icons / assets
- Complications / Live Activities
- Activity rings chrome
- Park profiles / detection thresholds
- Long branded onboarding carousel (alpha)
