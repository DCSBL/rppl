# Post-mortem: Action Button Cycle Label (again)

> **Obsolete (2026-08):** Cycle Label removed from the product. Detection is automatic (`DetectionEngine`). Keep this post-mortem for historical Action Button pitfalls only.

**When:** 2026-08-11 → 2026-08-12
**Symptom:** Ultra Action Button → red “Workout / Cycle Label” → ~30s → Dutch “mislukt” / “Cycle Label has failed”. Label no change. On-screen **Cycle label** OK.
**Files:** `WakeTrackerWatch/CycleLabelIntent.swift`, `WatchSessionController.swift`, `Info.plist` (`WKBackgroundModes`)

This bite twice. Write down so next agent no re-invent wrong fix.

---

## What fail look like

| Signal | Meaning |
|--------|---------|
| Red blob, **no** title, **no** `perform` logs | Often `openAppWhenRun = true` under Water Lock / active workout. System abort before intent body. |
| Red + **“Cycle Label”** title → ~30s fail | Intent armed. `perform` never finish (or never enter). App Intent hard timeout. |
| On-screen Cycle label works | Store / `LabelCodes` / session fine. Bug in Action Button / AppIntent path only. |
| `Mode: sensorsOnly` | Next-action donate need live `HKWorkoutSession`. Workout mode required. |

---

## Wrong rabbit holes (we go here first)

1. **App Group / iPhone embed** — group ID mismatch real (`AppConstants` vs entitlements) but Cycle Label write Documents. Not this fail.
2. **“Just schedule Task, return `.result()`”** — help only *after* `perform` already running. If `perform` itself MainActor-isolated, never start → still 30s fail.
3. **Nested `donate` + dialog inside Cycle Label** — can hang; Apple Mark Lap = plain `.result()`. Already slimmed.
4. **`workout-processing` under `UIBackgroundModes`** — wrong key. Need **`WKBackgroundModes`**. Fixed earlier; still required.

---

## Real root (last time)

Watch target:

```text
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

So `CycleLabelIntent.perform` become **implicit `@MainActor`**.

Action Button confirmation UI hold MainActor, wait for intent result.
`perform` need MainActor to start.
Deadlock. Timeout. “mislukt”.
No label. Maybe no `perform begin` log.

**Fix that stick:**

- `openAppWhenRun = false` on `CycleLabelIntent` (Water Lock)
- `nonisolated func perform()` on Cycle Label (and Start)
- Inside Cycle Label: **do not `await` MainActor**. `scheduleCycleLabelFromActionButton()` → `Task { @MainActor in … }` then **immediate** `return .result()`
- Donate next action when HK state → `.running` + after UI start (`donateActionButtonCycleIntent`)
- `WKBackgroundModes` = `workout-processing`

---

## Checklist next time Action Button break

1. Real Ultra preferred (sim next-action flaky).
2. Scheme **WakeTrackerWatch**, paired iPhone+Watch, Cmd+R.
3. Session `Mode: workout`. Log `donate Action Button OK`.
4. Press Action Button. Console need:
   - `CycleLabelIntent.perform begin`
   - `CycleLabelIntent.perform returned (cycle scheduled)`
   - `cycle waiting → riding` (or next code)
5. If title show + 30s fail + **no** begin log → suspect MainActor isolation on `perform` again.
6. If begin log + hang before returned → something still `await` MainActor inside `perform`.
7. Fallback: Settings → Action Button → **Shortcut** → Cycle Label (bypass workout next-action).

---

## Agent rules (short)

- No invent App Group / WC embed as first guess for this symptom.
- No “fix” that leave `perform` on MainActor while `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Keep Cycle Label `perform` **`nonisolated`** + no await of `WatchSessionController` on critical path.
- On-screen button ≠ Action Button path. Split-test both.

See also: [DataCollection.md](../DataCollection.md) (Action Button wire), [DevWorkflow.md](../DevWorkflow.md) (paired Cmd+R).
