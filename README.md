# Wake Tracker

**Cable-park wakeboarding, captured on Watch — labels included.**

Native iPhone + Apple Watch app that records a full park day as one continuous workout session: GPS, motion, heart rate, and coarse Action Button labels (`waiting` → `riding` → `swimming` → `walking`). Phone stays view-only: sync, map, export. Analysis happens on Mac.

Alpha first. Ugly is fine. Lost park days are not.

## Why this exists

Cable parks are repetitive loops — dock, ride, fall, swim, walk back — not open-water freestyle. Wake Tracker collects **labeled sensor corpora** from instructed testers so later phases can detect starts and segments automatically. No tricks yet. No App Store polish yet.

## MVP (Phases 1–2) — distilled

| Locked choice | Decision |
|---------------|----------|
| Platforms | iPhone + Watch only · iOS / watchOS **26+** |
| Test gear | iPhone 16 Pro + Apple Watch Ultra 2 |
| Audience | Alpha testers · data collection > product UX |
| Session | One `HKWorkoutSession` per park day · Start / Stop on Watch · **no pause** |
| Labels | Action Button cycles opaque string codes · Start logs `waiting` at t0 |
| Phone | View-only list / map / Share-Export · **no label editor** |
| HealthKit | Session for sensors · **do not `finishWorkout()`** · still mirror HR/energy into files |
| Transfer | Phone may be away · WC after Stop · **never delete Watch data until phone ack** |
| Water Lock | On at session start |
| Identity | Anonymous `testerId` in UserDefaults / App Group |
| Core | Pure logic in `WakeTrackerCore` · unit-tested with `swift test` |

**Park-day ready when:** Start/Stop + Water Lock, checkpointed GPS/motion/HR, Action Button labels with enriched snapshots, reliable WC transfer + ack, iPhone export, Core tests green.

### Later

- **Phase 3** — Auto-detection from labeled fixtures (Core), live Watch state + manual override · roadmap: [Docs/Phase3.md](Docs/Phase3.md) · ideas: [Docs/Ideas.md](Docs/Ideas.md)
- **Phase 4** — Product UI, HealthKit saves, CloudKit sync, heatmap polish

## Repo layout

```
WakeTrackerCore/     Shared models, IO, sync/label helpers (SPM + Swift Testing)
WakeTrackerWatch/    Session engine, sensors, Action Button, WC send
wake-tracker/        iPhone permissions, sync receive, map, export
Docs/                DataCollection, DevWorkflow, Phase3, Ideas
scripts/git-hooks/   pre-commit xcode gate
```

## Quick start

1. Open `wake-tracker.xcodeproj` in Xcode 26+.
2. Select the **wake-tracker** scheme (embeds Watch).
3. Run on device pair when possible — Simulator is weak for HealthKit / motion / WC.
4. Ultra Action Button: **Settings → Action Button → Workout → Wake Tracker**.

Dev gate (tests + lint + build + analyze):

```bash
brew install pre-commit swiftlint codespell
pre-commit install
make check
```

Details: [Docs/DevWorkflow.md](Docs/DevWorkflow.md) · streams & labels: [Docs/DataCollection.md](Docs/DataCollection.md).

## Bundle IDs

- iOS: `nl.dcsbl.wake-tracker`
- watchOS: `nl.dcsbl.wake-tracker.watchkitapp`
- App Group: `group.nl.dcsbl.wake-tracker`

## Agents

Coding agents: read [AGENTS.md](AGENTS.md) before changing architecture or session/sync behavior.
