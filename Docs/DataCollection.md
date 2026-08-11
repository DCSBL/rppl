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

`HKWorkoutSession` + builder run for sensors/runtime. **Do not call `finishWorkout()`** — alpha keeps personal Health clean.

## Transfer

Phone may be away during the session. After **Stop session**, Watch queues a WC file transfer and **keeps checkpoints until the phone sends an ack**. Transfer failure must not delete Watch data.

## Export

On iPhone: open a session → **Export session JSON** (Share/AirDrop to Mac for manual analysis).
