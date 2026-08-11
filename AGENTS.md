# AGENTS.md — Wake Tracker

Instructions for AI coding agents working in this repo.

## Communication: caveman

This project uses **caveman** mode for agent ↔ human chat.

- Default intensity: **full** (drop articles/filler; fragments OK; keep technical accuracy).
- Switch: `/caveman lite|full|ultra|wenyan-*|off` or `stop caveman` / `normal mode`.
- Skill: user `caveman` skill (and related `caveman-*` skills).
- **Do not** write README, AGENTS, commits, PR bodies, or other repo docs in caveman. Those stay normal prose.
- Chat replies: caveman while active. Code, comments, docs, commit messages: normal.

## Product north star

Alpha **data collector** for cable-park wakeboarding. Not a polished consumer tracker yet.

- Watch records; iPhone views/exports; Mac analyzes.
- Prefer reliable checkpoints over pretty UI.
- Prefer extending opaque string label codes over closed Swift enums.
- Prefer pure logic in `WakeTrackerCore` so `swift test` covers it without device APIs.

Distilled product lock: [README.md](README.md). Streams/labels/transfer: [Docs/DataCollection.md](Docs/DataCollection.md). Pre-commit gate: [Docs/DevWorkflow.md](Docs/DevWorkflow.md).

## Architecture rules

| Layer | Own | Avoid |
|-------|-----|--------|
| `WakeTrackerCore` | Models, schema, file store, `LabelCodes`, `LabelEventFactory`, `SyncConnectionResolver`, transfer filters | UIKit/SwiftUI, WCSession, HealthKit, CoreLocation |
| `WakeTrackerWatch` | `HKWorkoutSession` dry-run, sensors, Action Button intents, WC send, thin probes | Business decisions that can be pure functions |
| `wake-tracker` (iOS) | Permissions, WC receive/ack, session list/map/export, thin probes | Label editing (Phase 2), session engine |

App probes read live `WCSession` / sensors, then call Core resolvers/factories. Do not duplicate decision trees in both targets.

## Hard constraints (do not “helpfully” break)

1. **HealthKit dry-run:** use workout session + builder for runtime/sensors; **do not `finishWorkout()` / save to Health** in alpha. Still mirror HR/active energy into our JSONL.
2. **Never delete Watch session files until phone ack** after WC transfer. Failed transfer = keep data.
3. **One continuous session per park day**; no pause unless product decision changes.
4. **Label codes are strings** (`waiting`, `riding`, `swimming`, `walking`, …). Unknown codes must round-trip. No closed enum for taxonomy yet.
5. **iPhone Phase 2 = view-only** — no label editor.
6. **OS floor:** iOS 26+ / watchOS 26+.
7. **Water Lock** on session start.

## Testing

- Source of truth: `cd WakeTrackerCore && swift test` (Swift Testing).
- Expand Core tests for pure logic; keep `wake-trackerTests` thin.
- Do **not** unit-test SwiftUI, real `HKWorkoutSession`, `CLLocationManager`, or `WCSession` in the gate.
- Pre-commit runs: hygiene → codespell → SwiftLint → `scripts/git-hooks/xcode-gate.sh` (Core tests, `xcodebuild` build, analyze).
- Manual full gate: `make check`. Escape hatch only in emergency: `SKIP=xcode-gate` or `--no-verify`.

## Git / commits

- User often wants **frequent commits** after meaningful chunks. Ask if unclear; when asked, follow user git rules (no force-push, no `--no-verify` unless requested, HEREDOC messages).
- Do not commit secrets, `Exports/`, DerivedData, or `tools/bin` binaries (gitignored).
- Commit messages: normal prose, Conventional Commits style OK; not caveman.

## What to touch for common tasks

| Task | Start here |
|------|------------|
| Label cycle / next code | `WakeTrackerCore/.../LabelCodes.swift`, `LabelEventFactory.swift` |
| Sync status wording / branches | `SyncConnectionResolver.swift` + thin `SyncConnectionProbe.swift` in each app |
| On-disk format / ack / pending transfer | `SessionFileStore.swift`, `Models.swift` |
| Watch record loop | `WakeTrackerWatch/WatchSessionController.swift` |
| Action Button / workout next action | `WakeTrackerWatch/CycleLabelIntent.swift` |
| Phone sync + export UI | `wake-tracker/PhoneConnectivityService.swift`, `ContentView.swift` |
| Gate / lint | `.pre-commit-config.yaml`, `.swiftlint.yml`, `scripts/git-hooks/` |

## Out of scope unless explicitly asked

- GitHub Actions CI (can mirror `xcode-gate` later)
- UI tests in the commit gate
- Trick detection / full taxonomy
- CloudKit / HealthKit workout saves (Phase 4)
- Auto-format rewriting files in hooks (lint-only for now)
- Rewriting Docs or README into caveman

## When unsure

Prefer the locked Defaults in the MVP plan / README over inventing product behavior. If a change forks UX (pause, phone labeling, Health saves, deleting Watch data early), **stop and ask**.
