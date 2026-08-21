# HIG UI / interaction backlog

Apple HIG audit notes for Rppl Watch + iPhone (UI and interaction only).  
App icons / marketing assets stay out of scope.

Sibling PRs in the first pass shipped clear interaction fixes. Items below stay open until product decides, device testing lands, or a follow-up PR ships.

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

Graphite stack unavailable — these are independent PRs off `main`. `#52`, `#54`, and `#55` all touch `SessionRideUIPage.swift` (expect small conflicts).

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

## Open — needs product / device decision

### Watch: session end summary

After `stopSession`, UI returns to idle with no summary. HIG Workouts expects recorded stats when a session ends.

**Open questions:** what to show (duration / distance / rides only vs transfer status)? When does transfer UI take over? Auto-dismiss vs Done button?

**Touches:** Watch lifecycle + new summary view; coordinate with transfer / ack copy.

### Watch: Always On / reduced luminance

No `isLuminanceReduced` handling. HIG Always On: dim secondary chrome, keep primary metric, stable layout (don’t remove controls).

**Blocked on:** wrist Always On device check (Ultra + non-Ultra). Prefer ship after a park-day glance test.

**Touches:** [`SessionRideUIPage.swift`](../RpplWatch/Views/SessionRideUIPage.swift), [`SessionControlsPage.swift`](../RpplWatch/Views/SessionControlsPage.swift).

### iPhone: `TabBarLeadingAligner` private platter pin

[`TabBarLeadingAligner.swift`](../Rppl/App/TabBarLeadingAligner.swift) walks UIKit for a `"Platter"` subview and mutates its frame so the floating tab bar hugs the leading edge. Fragile vs iOS 26 tab-bar internals; nonstandard.

**Open questions:** keep visual preference and accept breakage risk, drop the hack (accept centered capsule), or find a supported API / different chrome?

### Watch: brand colors vs system appearance

[`RpplColor.swift`](../RpplWatch/Theme/RpplColor.swift) uses hardcoded RGB; idle pages force dark teal while the active ride UI uses system `.primary` / `.secondary`.

**Open questions:** move to asset catalog with light/dark (+ Increase Contrast), or keep forced “park night” brand on idle only?

### iPhone: Logbook card crowding at large Dynamic Type

[`SessionCard`](../Rppl/Logbook/LogbookView.swift) packs four caption stats in one `HStack`; Totals uses a three-metric strip. Likely clips or wraps badly above default sizes.

**Open questions:** 2×2 grid vs horizontal scroll vs hide secondary stats at accessibility sizes? Needs a large-type screenshot pass before picking a layout.

### Watch: tiny-session discard / cancel

HIG Workouts: auto-discard or ask if the session ends after only a few seconds. Not implemented.

**Open questions:** threshold duration? Always ask vs auto-discard? How this interacts with phone transfer / “never delete until ack”.

## Reference links

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
