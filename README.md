# Rppl

**Cable-park wakeboarding, captured on Watch — rides and pauses detected.**

Native iPhone + Apple Watch app that records a full park day as one continuous workout session: GPS, motion, heart rate, and automatic ride/pause detection. Phone stays view-only: sync, map, export. Analysis happens on Mac.

Alpha first. Ugly is fine. Lost park days are not.

## Why this exists

Cable parks are repetitive loops — dock, ride, fall, swim, walk back — not open-water freestyle. Rppl collects **sensor corpora** from instructed testers so later phases can measure ride length, rounds, and balance. No tricks yet. No App Store polish yet.

## MVP (Phases 1–2) — distilled

| Locked choice | Decision |
|---------------|----------|
| Platforms | iPhone + Watch only · iOS / watchOS **26+** |
| Test gear | iPhone 16 Pro + Apple Watch Ultra 2 |
| Audience | Alpha testers · data collection > product UX |
| Session | One `HKWorkoutSession` per park day · Start / Stop on Watch · **no pause** |
| Detection | Live ride / inactive / unsure → `detections.jsonl` · no manual Action Button labels |
| Phone | View-only list / map / Share-Export · **no label editor** |
| HealthKit | Save workout via `finishWorkout()` · `waterSports` (wakeboard MET) · HK session stays running · ride + dock HK activities · ride-scoped energy · ride-gated distance samples + GPS route · HR/energy mirrored into files |
| Transfer | Phone may be away · WC after Stop · **never delete Watch data until phone ack** |
| Water Lock | On at session start |
| Identity | Anonymous `testerId` in UserDefaults / App Group |
| Core | Pure logic in `RpplCore` · unit-tested with `swift test` |

**Park-day ready when:** Start/Stop + Water Lock, checkpointed GPS/motion/HR, live detection with reasons, reliable WC transfer + ack, iPhone export, Core tests green.

### Detection (Phase 3)

Watch runs a pure Core **detector + merger** (`DetectionEngine`) that writes opaque codes into `detections.jsonl`:

| Code | Meaning |
|------|---------|
| `inactive` | Not riding (dock / swim / walk / wait) |
| `riding` | On the cable / skimming at ride speed |
| `unsure` | Mid-ride GPS soft; primary UI keeps last confident code |

Writes **only on transitions** (+ `session_start`) and lookback revisions (`supersedesId`). Speeds in `reason` strings use **km/h**. Offline: `DetectionEngine.replay(ticks:)` / `replay(locations:)`.

Pipeline: GPS filter → hold clocks → detectors (`ride_enter`, `ride_exit`, `gps_gap`, `unsure_timeout`) → merger lookback (&lt; 60 s same ride). Ultra `submerged` logged only; motion activity logged only.

Thresholds and roadmap: [Docs/Phase3.md](Docs/Phase3.md). **Intern guide (start/stop detection):** [Docs/RideDetection.md](Docs/RideDetection.md). Library UML: [RpplCore/DESIGN.md](RpplCore/DESIGN.md). System map: [Docs/DESIGN.md](Docs/DESIGN.md).

### Later

- **Phase 3 continued** — Mac timeline viz (detections lane, threshold scrubbers), ride-length / rounds metrics · [Docs/Phase3.md](Docs/Phase3.md) · [Docs/Ideas.md](Docs/Ideas.md)
- **Phase 4** — Product UI, CloudKit sync, heatmap polish

## Repo layout

```
RpplCore/     Shared models, IO, DetectionEngine (SPM + Swift Testing) · DESIGN.md
RpplWatch/    Session engine, sensors, StartWorkoutIntent, WC send
Rppl/         iPhone permissions, sync receive, map, export
Docs/                DataCollection, SessionStorage, DevWorkflow, Phase3, Ideas, DESIGN (system)
scripts/git-hooks/   pre-commit lint; pre-push xcode gate
```

## Quick start

1. Open `Rppl.xcodeproj` in Xcode 26+.
2. Device pair (recommended): scheme **RpplWatch**, destination **iPhone + Watch**, Cmd+R — installs companion + Watch together. Details: [Docs/DevWorkflow.md](Docs/DevWorkflow.md).
3. Or phone-first: scheme **Rppl** (embeds Watch) → physical iPhone → Cmd+R, then open Watch app.
4. Simulator is weak for HealthKit / motion / WC — prefer the device pair.
5. Ultra Action Button (optional): **Settings → Action Button → Workout → Rppl** starts a session only.

Dev gate (lint on commit; Core tests + incremental `xcodebuild` on push when app/build files change; `make check` adds analyze):

```bash
brew install pre-commit swiftlint codespell
pre-commit install   # installs pre-commit + pre-push
make check
```

Details: [Docs/DevWorkflow.md](Docs/DevWorkflow.md) · streams & detection: [Docs/DataCollection.md](Docs/DataCollection.md) · Core design: [RpplCore/DESIGN.md](RpplCore/DESIGN.md).

## Bundle IDs (current `.dev` builds)

- iOS: `nl.dcsbl.rppl`
- watchOS: `nl.dcsbl.rppl.watchkitapp` (must be `{iOS}.watchkitapp`)
- Companion: Watch → iPhone ID above
- App Group: `group.nl.dcsbl.rppl`

## Privacy & legal

Hobby project (Netherlands). No Rppl cloud: session data is processed on your Watch and iPhone. It stays on your devices, in Apple Health when you allow it, and in your iCloud backup if you back up that device. We do not sell or share your data unless you explicitly choose to (for example export, or a connection you enable).

| Doc | Role |
|-----|------|
| [LEGAL.md](LEGAL.md) | Full Terms & Privacy (English; Dutch/EU law). Same substance as in-app **rppl → Legal**. |
| [LICENSE](LICENSE) | Source code (MIT). Separate from app Terms & Privacy. |

Contact: [rppl@dcsbl.nl](mailto:rppl@dcsbl.nl).

## Agents

Coding agents: read [AGENTS.md](AGENTS.md) before changing architecture or session/sync behavior. Library shape: [RpplCore/DESIGN.md](RpplCore/DESIGN.md). System layers: [Docs/DESIGN.md](Docs/DESIGN.md).
