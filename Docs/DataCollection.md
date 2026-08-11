# Data collection (Phase 2)

Alpha collector for cable-park wakeboarding. Tracking runs only on Apple Watch.

## Label codes (Action Button)

Cycle: `waiting` → `riding` → `swimming` → `walking` → …

- **Start session** writes `waiting` at t0.
- Each Action Button press (or on-screen **Cycle label**) advances and logs the new code.
- Assign Ultra Action Button to the **Cycle Label** shortcut in Watch Settings.

Label events store: `code`, `timestamp`, latest GPS snapshot, optional water submersion/temp, optional motion-activity hint. High-rate motion/HR live in chunk files and are joined by time offline.

## Streams

| Stream | Approx rate | File |
|--------|-------------|------|
| GPS | Core Location updates | `location-000.jsonl` |
| deviceMotion | ~50 Hz | `motion-000.jsonl` |
| HR / active energy (mirrored, not saved to Health) | workout builder | `health-000.jsonl` |
| Labels | on events | `labels.jsonl` |
| Manifest | once | `manifest.json` |

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime. Starting a session requires **share** authorization for Workouts (even though we **do not call `finishWorkout()`**).

If Health denies workout sharing (common after tapping Don’t Allow, or flaky on Simulator), the Watch continues in **sensors-only** mode: GPS + labels still record; HR/energy from the builder are skipped.

## Action Button (Ultra)

Cycle Label is **not** a top-level Action Button menu item (flashlight / workout / shortcut). Wire it like a workout app:

1. Settings › Action Button › **Workout**
2. App › **Wake Tracker** (Cable Park)
3. First press starts the session; later presses run **Cycle Label** (donated as the workout “next action”)

Requires an active HealthKit workout session (`Mode: workout`). Sensors-only mode cannot arm the Action Button next action.

## Transfer

Phone may be away during the session. After **Stop session**, Watch queues a WC file transfer and **keeps checkpoints until the phone sends an ack**. Transfer failure must not delete Watch data.

## Export

On iPhone: open a session → **Export session JSON** (Share/AirDrop to Mac for manual analysis).
