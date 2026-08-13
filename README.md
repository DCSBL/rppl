# Rppl

**Cable-park wakeboarding, captured on Watch — Assumer segment codes included.**

Native iPhone + Apple Watch app that records a full park day as one continuous workout session: GPS, motion, heart rate, and auto-proposed segment codes (`waiting`, `riding`, `swimming`, `walking`). Phone stays view-only: sync, map, export. Analysis happens on Mac.

Alpha first. Ugly is fine. Lost park days are not.

## Why this exists

Cable parks are repetitive loops — dock, ride, fall, swim, walk back — not open-water freestyle. Rppl collects **sensor corpora with Assumer segment codes** from instructed testers so later phases can tune detection. No tricks yet. No App Store polish yet.

## MVP (Phases 1–2) — distilled

| Locked choice | Decision |
|---------------|----------|
| Platforms | iPhone + Watch only · iOS / watchOS **26+** |
| Test gear | iPhone 16 Pro + Apple Watch Ultra 2 |
| Audience | Alpha testers · data collection > product UX |
| Session | One `HKWorkoutSession` per park day · Start / Stop on Watch · **no pause** |
| Segment codes | Assumer writes opaque string codes · Start logs `waiting` at t0 |
| Phone | View-only list / map / Share-Export · **no label editor** |
| HealthKit | Session for sensors · **do not `finishWorkout()`** · still mirror HR/energy into files |
| Transfer | Phone may be away · WC after Stop · **never delete Watch data until phone ack** |
| Water Lock | On at session start |
| Identity | Anonymous `testerId` in UserDefaults / App Group |
| Core | Pure logic in `RpplCore` · unit-tested with `swift test` |

**Park-day ready when:** Start/Stop + Water Lock, checkpointed GPS/motion/HR, Assumer assumptions with reasons, reliable WC transfer + ack, iPhone export, Core tests green.

### Assumption algorithm (Phase 3 slice — live)

Watch runs a pure Core FSM (`SegmentAssumer`) that proposes opaque segment codes into `assumptions.jsonl`:

| Stream | File | Who writes |
|--------|------|------------|
| Auto assumptions | `assumptions.jsonl` | Assumer on code change (+ `session_start`) |
| Legacy manual labels | `labels.jsonl` | Empty for new sessions; still decoded for old exports |

Each assumption line carries a `reason` with speeds in **km/h**. Watch shows the assumed code as primary UI; phone lists reasons and Share-export includes `assumptions`.

Pipeline (filter → holds → ordered rules):

1. **Filter noisy GPS** — reject nil / bad accuracy / implausible speed / sudden jumps for *speed* rules; Ultra `submerged` can still force swim.
2. **Hold clocks** — require sustained speed bands (e.g. ≥15 km/h for 2 s to enter `riding`).
3. **Transition rules** — first matching edge wins (`ride_start`, `fall_swim`, `failed_start`, `long_stop`, `water_start`, walk/wait settle).

Ultra-first: auto-`swimming` needs water submersion. Thresholds and roadmap: [Docs/Phase3.md](Docs/Phase3.md). Library UML + how to add rules: [RpplCore/DESIGN.md](RpplCore/DESIGN.md). System sequence: [Docs/DESIGN.md](Docs/DESIGN.md).

### Later

- **Phase 3 continued** — Mac timeline viz (assumed lane, threshold scrubbers), then optional live override UX · [Docs/Phase3.md](Docs/Phase3.md) · [Docs/Ideas.md](Docs/Ideas.md)
- **Phase 4** — Product UI, HealthKit saves, CloudKit sync, heatmap polish

## Repo layout

```
RpplCore/     Shared models, IO, Assumer FSM (SPM + Swift Testing) · DESIGN.md
RpplWatch/    Session engine, sensors, WC send
Rppl/        iPhone permissions, sync receive, map, export
Docs/                DataCollection, DevWorkflow, Phase3, Ideas, DESIGN (system)
scripts/git-hooks/   pre-commit xcode gate
```

## Quick start

1. Open `Rppl.xcodeproj` in Xcode 26+.
2. Device pair (recommended): scheme **RpplWatch**, destination **iPhone + Watch**, Cmd+R — installs companion + Watch together. Details: [Docs/DevWorkflow.md](Docs/DevWorkflow.md).
3. Or phone-first: scheme **Rppl** (embeds Watch) → physical iPhone → Cmd+R, then open Watch app.
4. Simulator is weak for HealthKit / motion / WC — prefer the device pair.

Dev gate (tests + lint + build + analyze):

```bash
brew install pre-commit swiftlint codespell
pre-commit install
make check
```

Details: [Docs/DevWorkflow.md](Docs/DevWorkflow.md) · streams & labels: [Docs/DataCollection.md](Docs/DataCollection.md) · Core design: [RpplCore/DESIGN.md](RpplCore/DESIGN.md).

## Bundle IDs (current `.dev` builds)

- iOS: `nl.dcsbl.dev.rppl`
- watchOS: `nl.dcsbl.dev.rppl.watchkitapp` (must be `{iOS}.watchkitapp`)
- Companion: Watch → iPhone ID above
- App Group: `group.nl.dcsbl.dev.rppl`

## Agents

Coding agents: read [AGENTS.md](AGENTS.md) before changing architecture or session/sync behavior. Library shape: [RpplCore/DESIGN.md](RpplCore/DESIGN.md). System layers: [Docs/DESIGN.md](Docs/DESIGN.md).
