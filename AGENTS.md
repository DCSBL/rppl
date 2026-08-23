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

Distilled product lock: [README.md](README.md). Streams/detection/transfer: [Docs/DataCollection.md](Docs/DataCollection.md). Session on-disk layout: [Docs/SessionStorage.md](Docs/SessionStorage.md). Pre-commit gate: [Docs/DevWorkflow.md](Docs/DevWorkflow.md). Detection thresholds: [Docs/RideDetection.md](Docs/RideDetection.md). System design: [Docs/DESIGN.md](Docs/DESIGN.md). Core library UML / DetectionEngine: [RpplCore/DESIGN.md](RpplCore/DESIGN.md).

## Architecture rules

| Layer | Own | Avoid |
|-------|-----|--------|
| `RpplCore` | Models, schema, file store, `DetectionCodes`, `DetectionEngine` (+ filter/holds/detectors), `SyncConnectionResolver`, transfer filters | UIKit/SwiftUI, WCSession, HealthKit, CoreLocation |
| `RpplWatch` | `HKWorkoutSession` + Health save, sensors, StartWorkoutIntent, WC send, thin detection probes | Business decisions that can be pure functions |
| `Rppl` (iOS) | Permissions, WC receive/ack, session list/map/export, thin probes | Label editing, session engine |

App probes read live `WCSession` / sensors, then call Core resolvers/engines. Do not duplicate decision trees in both targets. Layer diagram: [Docs/DESIGN.md](Docs/DESIGN.md).

## Hard constraints (do not “helpfully” break)

1. HealthKit save — `stopActivity` → wait `.stopped` → `endCollection` → **`finishWorkout()`** → `session.end()`. Still mirror HR / active (and basal) energy into JSONL. Keep the HK session **running** during detection `inactive`; `beginNewActivity` on each confident `riding` and `inactive` (Fitness numbered intervals). Disable active-energy + distance collection while docked. No `motionPaused` on detection rest. **`session.pause()` only for product Pause**. Never `HKWorkoutEvent.lap` unless Fitness can show a lap count. See hard constraint 3.
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

## Git / commits

- User often wants **frequent commits** after meaningful chunks. Ask if unclear; when asked, follow user git rules (no force-push, no `--no-verify` unless requested, HEREDOC messages).
- Do not commit secrets, `Exports/`, DerivedData, or `tools/bin` binaries (gitignored).
- Commit messages: normal prose, Conventional Commits style OK; not caveman.

## What to touch for common tasks

| Task | Start here |
|------|------------|
| Ride/pause detection | `DetectionEngine.swift`, `Detectors.swift`, `DetectionThresholds.swift` · [Docs/RideDetection.md](Docs/RideDetection.md) · [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Session stats (derived) | `SessionStatsBuilder.swift`, `LiveRideTracker.swift`, `GeoDistance.swift` · [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Sync status wording / branches | `SyncConnectionResolver.swift` + thin `SyncConnectionProbe.swift` in each app |
| On-disk format / ack / pending transfer | `SessionFileStore.swift`, `Models.swift` |
| Watch record loop | `RpplWatch/WatchSessionController.swift` |
| Start session Action Button | `RpplWatch/StartWorkoutIntent.swift` (StartWorkoutIntent only) |
| Phone sync + export UI | `Rppl/PhoneConnectivityService.swift`, `ContentView.swift` |
| Gate / lint | `.pre-commit-config.yaml`, `.swiftlint.yml`, `scripts/git-hooks/` |
| GitHub PR checks | `.github/workflows/pr-checks.yml` · [Docs/DevWorkflow.md](Docs/DevWorkflow.md) |
| System / Core design (UML) | [Docs/DESIGN.md](Docs/DESIGN.md), [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |

## Out of scope unless explicitly asked

- GitHub Actions macOS / `xcode-gate` mirror (PR Linux pre-commit already in `.github/workflows/`)
- UI tests in the push gate
- Trick detection / full taxonomy
- CloudKit sync
- Auto-format rewriting files in hooks (lint-only for now)
- Rewriting Docs or README into caveman
- Park profiles / dock geofence hardcoding (Linear: DCSBL-56)
- Mac timeline viz or inventing detector thresholds without an explicit ask (Linear: DCSBL-60)

## When unsure

Prefer the locked Defaults in README over inventing product behavior. If a change forks UX (product pause, phone labeling, deleting Watch data early), **stop and ask**. Do not invent detector thresholds or park profiles without an explicit code ask — follow [Docs/RideDetection.md](Docs/RideDetection.md) and `DetectionThresholds` in Core.
