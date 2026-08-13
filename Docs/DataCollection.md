# Data collection (Phase 2)

Alpha collector for cable-park wakeboarding. Tracking runs only on Apple Watch.

## Segment codes (Assumer)

Opaque strings: `waiting`, `riding`, `swimming`, `walking`, …

- **Start session** writes Assumer `waiting` + `reason=session_start` at t0.
- Later transitions append to `assumptions.jsonl` only when the Assumer code changes.
- Watch UI shows the current assumed code as primary face text.

Assumption events store: `code`, `timestamp`, `reason` (km/h speeds), optional speed/water/activity snapshot. High-rate motion/HR live in chunk files and are joined by time offline. Motion is **25 Hz**, compact JSON keys, and **framed zlib** on disk (`motion-000.jsonl.zlib`) so a park day stays transferable; WC packages carry `motionFramesZlib` instead of expanding every sample into JSON.

Legacy packages may still contain `labels.jsonl` (manual ground truth from older builds). New sessions keep an empty `labels.jsonl` for schema stability; phone still lists/decodes it when present. Dual-stream history: [DESIGN.md](DESIGN.md) · Core UML: [../RpplCore/DESIGN.md](../RpplCore/DESIGN.md) · thresholds: [Phase3.md](Phase3.md).

## Streams

| Stream | Approx rate | File |
|--------|-------------|------|
| GPS | Core Location updates | `location-000.jsonl` |
| deviceMotion | ~25 Hz → framed zlib JSONL | `motion-000.jsonl.zlib` |
| HR / active energy (mirrored, not saved to Health) | workout builder | `health-000.jsonl` |
| Assumptions | on Assumer transitions | `assumptions.jsonl` |
| Labels (legacy / empty) | historical packages | `labels.jsonl` |
| Manifest | once | `manifest.json` |

## HealthKit policy

`HKWorkoutSession` + builder run for sensors/runtime. Starting a session requires **share** authorization for Workouts (even though we **do not call `finishWorkout()`**).

If Health denies workout sharing (common after tapping Don’t Allow, or flaky on Simulator), the Watch continues in **sensors-only** mode: GPS + Assumer still record; HR/energy from the builder are skipped.

## Transfer

Phone may be away during the session. After **Stop session**, Watch queues a WC file transfer and **keeps checkpoints until the phone sends an ack**. Transfer failure must not delete Watch data. Transfer package includes `assumptions` when present (legacy packages without the key decode as empty).

## Export

On iPhone: open a session → **Export session JSON** (Share/AirDrop to Mac for manual analysis). Export includes `labels` (often empty) and `assumptions`.
