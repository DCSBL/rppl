# AGENTS.md — Rppl

Instructions for AI coding agents working in this repo.

## Communication: caveman

This project uses **caveman** mode for agent ↔ human chat.

- Default intensity: **full** (drop articles/filler; fragments OK; keep technical accuracy).
- Switch: `/caveman lite|full|ultra|wenyan-*|off` or `stop caveman` / `normal mode`.
- Skill: user `caveman` skill (and related `caveman-*` skills).
- **Do not** write README, AGENTS, commits, PR bodies, or other repo docs in caveman. Those stay normal prose.
- Chat replies: caveman while active. Code, comments, docs, commit messages: normal.

## Source management
- Always work on a worktree
- Commit changes, even small changes in increments. Keep title and description as small and concrete as possible.
- A worktree will be squashed and merged via a GitHub PR by human.
- **PR title** (not necessarily each commit): `<component>(<type>): <short description>` — e.g. `watch(feat): …`, `slang(fix): …`. See [contributions/agent.md](contributions/agent.md).
- Each commit triggers light `pre-commit` hooks; each push runs `xcode-gate` only when build-related files change (Swift, plist, Xcode project, Package.swift, …). Docs/YAML/unrelated scripts skip it. Pass all checks; resolve issues when needed.

## Linear issues
_Only use linear issues when one is given by the user_
- When starting work on a Linear issue: set status **In Progress**.
- When finished (merged, or ready on the branch when the user asked to ship): set status **Done**.

## Product north star

**Data collector** for cable-park wakeboarding — Watch records; reliable checkpoints over flashy UX.

- Watch records; iPhone views/exports; Mac analyzes.
- Prefer reliable checkpoints over pretty UI.
- Prefer extending opaque string detection codes over closed Swift enums.
- Prefer pure logic in `RpplCore` so `swift test` covers it without device APIs.

Product defaults: [CONTRIBUTING.md](CONTRIBUTING.md). Streams/detection/transfer: [Docs/DataCollection.md](Docs/DataCollection.md). Session on-disk layout: [Docs/SessionStorage.md](Docs/SessionStorage.md). Pre-commit gate: [Docs/DevWorkflow.md](Docs/DevWorkflow.md). Detection thresholds: [Docs/RideDetection.md](Docs/RideDetection.md). System design: [Docs/DESIGN.md](Docs/DESIGN.md). Core library UML / DetectionEngine: [RpplCore/DESIGN.md](RpplCore/DESIGN.md).

## Wakeboard slang (all locales)

When generating, translating, or rewriting product copy about wakeboarding / cable parks **in any language**, keep authentic community slang and English jargon. Do not replace core terms with literal local equivalents — that reads amateurish in cable-park culture.

**Keep in English** (integrate into local grammar; conjugating loan verbs is fine where natural): `riding` / `ride` / `rides`, `session` / `sessions`, `set` / `sets`, `lap` / `laps`, `cable`, `dock`, `kicker`, `feature`, `rail`, `box`, `pop`, `cut in`, `boots` / `bindings`, `regular` / `goofy` / `switch`, `wipeout`, trick names (`Raley`, `Backroll`, …). Obstacle and trick names stay 100% English.

### Set vs lap (do not conflate)

#### 1. A set

A **set** is the total overall session/turn allocated to a single rider from the time they step onto the dock until their assigned time or turn is up.

- **Cable park:** A set usually means a specific block of time (e.g. a 10-minute set on a 2-tower system) or a set number of laps around a full-size cable (e.g. a “3-lap set”). During a set, if you fall, you walk back to the dock and use up the rest of your allocated time or remaining laps.
- **Boat:** Historically one rider behind the boat for roughly 15–20 minutes (or until a predetermined number of falls, e.g. 2–3) before switching with another passenger.
- **Glossary shorthand:** “a round of wakeboarding.”

Product language for turn allocation. **Not** what `LapRideTracker` counts.

#### 2. A lap

A **lap** is a distance measurement: one complete circuit around a full-size cable-park layout — starting at the main dock, passing every turn/tower corner in order, and making it all the way back to the dock without falling or letting go.

- **Usage:** “I'm going to do 3 laps and hit the kicker on the last one.”
- **Key distinction:** A single set often consists of multiple laps. If you fall halfway around the circuit on your first go, you completed half a lap, but your overall set continues until your time/turn ends.

Crossing counter (`LapRideTracker` / `lapCount`): leave start, path, re-enter → +1. UI labels **Laps**.

Never call a circuit crossing a “set”. Never call an allocated turn a “lap”. Derived JSON key is `lapCount` (accept legacy `setCount` from the short-lived slang mis-rename; encode `lapCount` only).

**Dutch anti-patterns** (NL is shipped today; same rule applies to future locales): avoid *varen*, *rijden*, *rit(ten)*, *ronde(s)* as stand-ins for ride/lap/set jargon, *schans*, *handvat*, *steiger*, *kabelbaan*, *aansnijden*, *afzet* for those concepts. Prefer e.g. *"aan het riden"*, *"session"*, *"set"*, *"lap(s)"*, *"dock"*, *"kicker"*, *"in-cutten"*, *"pop"*. Place name *kabelpark* is fine.

Glossary reference: [Nootica wakeboarding glossary](https://www.nootica.com/webzine/wakeboarding-glossary.html) (set ≈ round of wakeboarding; distinguish from lap = full circuit).

Applies to UI strings (`.xcstrings`), Info.plist usage text, App Store / marketing copy, and agent-written prose — not to detection code identifiers in Core (those stay opaque English strings per hard constraint 4).

## Architecture rules

| Layer | Own | Avoid |
|-------|-----|--------|
| `RpplCore` | Models, schema, file store, `DetectionCodes`, `DetectionEngine` (+ filter/holds/detectors), `SyncConnectionResolver`, transfer filters | UIKit/SwiftUI, WCSession, HealthKit, CoreLocation |
| `RpplWatch` | `HKWorkoutSession` + Health save, sensors, StartWorkoutIntent, WC send, thin detection probes | Business decisions that can be pure functions |
| `Rppl` (iOS) | Permissions, WC receive/ack, session list/map/export, thin probes | Label editing, session engine |

App probes read live `WCSession` / sensors, then call Core resolvers/engines. Do not duplicate decision trees in both targets. Layer diagram: [Docs/DESIGN.md](Docs/DESIGN.md).

## Hard constraints (do not “helpfully” break)

1. HealthKit save — `stopActivity` → wait `.stopped` → `endCollection` → **`finishWorkout()`** → `session.end()`. Still mirror HR / active (and basal) energy into JSONL. Keep the HK session **running** during detection `inactive`; `beginNewActivity` on each confident `riding` and `inactive` (Fitness numbered intervals). Disable active-energy + distance collection while docked. No `motionPaused` on detection rest. **`session.pause()` only for product Pause**. Never emit `HKWorkoutEvent.lap` unless Fitness can show a lap count we fill (Apple API). In-app cable **laps** stay in `LapRideTracker` / derived stats — do not confuse with product **sets** (allocated turn). See hard constraint 3 + Set vs lap above.
2. **Never delete Watch session files until phone ack** after WC transfer. Failed transfer = keep data.
3. **One continuous session per park day** by default. **Product Pause** (Watch controls) is allowed: freezes timers, stops sensors (data gap), pauses HK, writes `inactive` with `detectorId` `product_pause` / `product_resume`. Distinct from detection `inactive` (still recording, not riding).
4. **Detection codes are strings** (`riding`, `inactive`, `unsure`, …). Unknown codes must round-trip. No closed enum for taxonomy yet.
5. **iPhone = view-only** — no label editor; no manual Action Button labeling.
6. **OS floor:** iOS 26+ / watchOS 26+.
7. **Water Lock** on session start.

## Testing

- Source of truth: `cd RpplCore && swift test` (Swift Testing).
- Expand Core tests for pure logic; keep `RpplTests` thin.
- Do **not** unit-test SwiftUI, real `HKWorkoutSession`, `CLLocationManager`, or `WCSession` in the gate.
- Pre-commit (commit): hygiene → codespell → SwiftLint.
- Pre-push: `scripts/git-hooks/xcode-gate.sh` (Core tests; `xcodebuild` build if app/Core sources changed) when the push includes build-related files. Skips steps whose inputs match the last successful run. Analyze is `make check` / `XCODE_GATE_ANALYZE=1` only.
- Manual full gate: `make check`. Escape hatch only in emergency: `SKIP=xcode-gate` or `--no-verify`.

## Cloud Agents (Linux)

Cloud Agent VMs are Linux — same scope as [`.github/workflows/pr-checks.yml`](.github/workflows/pr-checks.yml), not a Mac with Xcode.

- **Do run:** `pre-commit run` (commit-stage hooks) and `make lint` (SwiftLint via `tools/bin/swiftlint`).
- **Do not expect:** `xcodebuild`, Simulator, HealthKit, Watch Connectivity, or a green `make check` / `make gate`.
- **`cd RpplCore && swift test`:** source of truth on macOS / Xcode Cloud. On Linux it currently fails (`import Compression` — Apple framework). Do not treat that failure as a Cloud Agent environment bug; keep Core pure where possible, but do not invent Linux shims unless explicitly asked.
- Optional: Swift toolchain may be present for Package.swift / editor use; it does not unlock iOS/watchOS app builds.

## Git / commits

- User often wants **frequent commits** after meaningful chunks. Ask if unclear; when asked, follow user git rules (no force-push, no `--no-verify` unless requested, HEREDOC messages).
- Do not commit secrets, `Exports/`, DerivedData, or `tools/bin` binaries (gitignored).
- Commit messages: normal prose, Conventional Commits style OK; not caveman.
- PR titles use component-first format: [contributions/agent.md](contributions/agent.md).

## What to touch for common tasks

| Task | Start here |
|------|------------|
| Ride/pause detection | `DetectionEngine.swift`, `Detectors.swift`, `DetectionThresholds.swift` · [Docs/RideDetection.md](Docs/RideDetection.md) · [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Session stats (derived) | `SessionStatsBuilder.swift`, `LiveRideTracker.swift`, `LapRideTracker.swift`, `GeoDistance.swift` · [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Sync status wording / branches | `SyncConnectionResolver.swift` + thin `SyncConnectionProbe.swift` in each app |
| On-disk format / ack / pending transfer | `SessionFileStore.swift`, `Models.swift` |
| Watch record loop | `RpplWatch/WatchSessionController.swift` |
| Start session Action Button | `RpplWatch/StartWorkoutIntent.swift` (StartWorkoutIntent only) |
| Phone sync + export UI | `Rppl/PhoneConnectivityService.swift`, `ContentView.swift` |
| Gate / lint | `.pre-commit-config.yaml`, `.swiftlint.yml`, `scripts/git-hooks/` |
| GitHub PR checks | `.github/workflows/pr-checks.yml` · [Docs/DevWorkflow.md](Docs/DevWorkflow.md) |
| System / Core design (UML) | [Docs/DESIGN.md](Docs/DESIGN.md), [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| UI / Info.plist copy (any locale) | `*.xcstrings` · `scripts/format-xcstrings.py` · Wakeboard slang section above |

## Out of scope unless explicitly asked

- GitHub Actions macOS / `xcode-gate` mirror (PR Linux pre-commit already in `.github/workflows/`)
- UI tests in the push gate
- Trick detection / full taxonomy
- CloudKit sync (Documents in iCloud for the phone logbook is in scope; prefer native ubiquity APIs)
- Auto-format rewriting **Swift** in hooks (lint-only; `.xcstrings` are an exception — Xcode-aligned via `scripts/format-xcstrings.py`)
- Rewriting Docs or README into caveman
- Park profiles / dock geofence hardcoding (Linear: DCSBL-56)
- Mac timeline viz or inventing detector thresholds without an explicit ask (Linear: DCSBL-60)

## When unsure

Prefer the product defaults in [CONTRIBUTING.md](CONTRIBUTING.md) over inventing product behavior. If a change forks UX (product pause, phone labeling, deleting Watch data early), **stop and ask**. Do not invent detector thresholds or park profiles without an explicit code ask — follow [Docs/RideDetection.md](Docs/RideDetection.md) and `DetectionThresholds` in Core.
