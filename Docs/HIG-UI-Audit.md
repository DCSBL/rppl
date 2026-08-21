# HIG UI / interaction backlog

Apple HIG audit notes for Rppl Watch + iPhone (UI and interaction only).  
Skip: onboarding, app icons / marketing assets.

Sibling PRs in this pass ship the clear, low-ambiguity fixes. Items below stay open until product decides or device testing lands.

## Shipped in this pass (see sibling PRs)

| Fix | Why (HIG) |
|-----|-----------|
| Watch Stop confirmation | Workouts / Feedback — confirm irreversible end |
| Phone export + delete failure alerts | Feedback — surface failed actions |
| Phone Logbook sync status | Feedback — companion connection in-context |
| Resume on paused metrics page | Gestures — visible control, not swipe-only |
| Start / Stop / Pause haptics | Playing haptics — Start/Stop for explicit control |
| MDI + control VoiceOver labels; idle sync stays tappable while starting | Accessibility |
| Ride timer Dynamic Type (drop fixed pt) | Typography / Accessibility |

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

- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Workouts](https://developer.apple.com/design/human-interface-guidelines/workouts)
- [Always On](https://developer.apple.com/design/human-interface-guidelines/always-on)
- [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)

## Explicitly out of scope here

- Onboarding
- Icons / assets
- Complications / Live Activities
- Activity rings chrome
- Park profiles / detection thresholds
