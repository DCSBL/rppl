<p align="center">
  <img src="assets/rppl.svg" alt="Rppl" width="140">
</p>

<h1 align="center">Rppl</h1>

<p align="center">
  <a href="https://github.com/DCSBL/rppl/actions/workflows/pr-checks.yml"><img src="https://img.shields.io/github/actions/workflow/status/DCSBL/rppl/pr-checks.yml?branch=main&label=PR%20checks" alt="PR checks"></a>
  <img src="https://img.shields.io/badge/iOS-26%2B-black?logo=apple&logoColor=white" alt="iOS 26+">
  <img src="https://img.shields.io/badge/watchOS-26%2B-black?logo=apple&logoColor=white" alt="watchOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/privacy-on%20device-0B6E4F" alt="Privacy: on device">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20NC-blue" alt="PolyForm Noncommercial"></a>
</p>

<p align="center"><strong>Cable-park wakeboarding, captured on Watch.</strong><br>
Rides and pauses detected. Phone syncs, maps, exports. No cloud. No subscriptions.</p>

## What it does

Watch records a full park day as one continuous workout: GPS, motion, heart rate, live ride / inactive / unsure detection. iPhone is view-only. Analysis stays on your Mac (or wherever you export).

Reliable checkpoints over pretty UI. Lost park days are not OK.

## A note from Duco

Hi! My name is Duco. Since this year I’ve often been at a cable park to wakeboard. The regular Apple Workout app is too basic, so I went looking for a better tracker. What I found was either too complex, too limited, full of subscriptions, or hungry for my data. That had to be different.

My background is embedded software, so iOS is new territory. This app was built almost entirely with AI help. After several test sessions I dare to make it public, in the hope that others get something out of it.

I hope that, like me, you enjoy tracking your sessions!

-- Duco

(Dutch original in [LEGAL.md](LEGAL.md).)

## Product lock (short)

| | |
|---|---|
| Brand | **Rppl** (capital R; never `RPPL` / `rppl` in UI copy) |
| Platforms | iPhone + Watch · iOS / watchOS **26+** |
| Session | One workout per park day · Start / Stop on Watch · product Pause allowed |
| Detection | Live codes into `detections.jsonl` · no manual labels |
| Phone | View / map / export only |
| Transfer | Never delete Watch data until phone ack |
| Core | Pure logic in `RpplCore` · `swift test` |

Full hard constraints: [AGENTS.md](AGENTS.md) · thresholds: [Docs/RideDetection.md](Docs/RideDetection.md).

## Leeswijzer

Where to look, without reading the whole tree:

| Want… | Open |
|-------|------|
| Product / agent rules | [AGENTS.md](AGENTS.md) |
| Layers Watch / iPhone / Core | [Docs/DESIGN.md](Docs/DESIGN.md) |
| DetectionEngine UML | [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Streams, HK, transfer, export | [Docs/DataCollection.md](Docs/DataCollection.md) |
| On-disk session layout | [Docs/SessionStorage.md](Docs/SessionStorage.md) |
| Ride / pause thresholds | [Docs/RideDetection.md](Docs/RideDetection.md) |
| Xcode, hooks, `make check` | [Docs/DevWorkflow.md](Docs/DevWorkflow.md) |
| Terms & privacy | [LEGAL.md](LEGAL.md) |

```
RpplCore/     models, IO, DetectionEngine (SPM + Swift Testing)
RpplWatch/    session, sensors, HealthKit, WC send
Rppl/         permissions, sync receive, map, export
Docs/         design + domain docs above
```

## Quick start

1. Open `Rppl.xcodeproj` in Xcode 26+.
2. Prefer scheme **RpplWatch**, destination **iPhone + Watch**, Cmd+R.
3. Simulator is weak for HealthKit / motion / WC. Use devices.

```bash
brew install pre-commit swiftlint codespell
pre-commit install
make check
```

More: [Docs/DevWorkflow.md](Docs/DevWorkflow.md).

Bundle IDs (`.dev`): `nl.dcsbl.rppl` · Watch `nl.dcsbl.rppl.watchkitapp` · App Group `group.nl.dcsbl.rppl`.

## Contribute

Bugs and ideas: [open an issue](https://github.com/DCSBL/rppl/issues).  
Suggested changes: open a PR. Small, focused diffs beat kitchen-sink branches.

**What fits**

- Fixes that protect capture, sync, ack, or export
- Core logic with tests (`cd RpplCore && swift test`)
- Docs that match reality
- UI only when it helps ride data, not decoration

**What usually does not**

- Cloud sync, accounts, subscriptions
- Trick taxonomy or closed detection enums (codes stay opaque strings)
- Phone-side label editors
- Inventing detector thresholds without measurement

**Quality bar**

- Prefer pure logic in `RpplCore` so tests run without device APIs
- Pre-commit (hygiene, codespell, SwiftLint) and push gate must stay green
- Wakeboard slang stays authentic in every locale (see [AGENTS.md](AGENTS.md))

**AI-assisted PRs**

AI tools are welcome. Autonomous drive-by PRs are not. If AI wrote it, you still own it: you must be able to explain the change in your own words, and you run the tests. Same bar whether you typed every line or vibed it. Inspired by the [Open Home Foundation AI policy](https://developers.home-assistant.io/blog/2026/07/20/ai-policy/).

Test. Test. Test.

## Privacy & license

Hobby project (Netherlands). No Rppl cloud. Session data stays on your devices, in Apple Health when allowed, and in your backups. We do not sell your data.

| Doc | Role |
|-----|------|
| [LEGAL.md](LEGAL.md) | Terms & Privacy (canonical; synced into the iPhone app) |
| [LICENSE](LICENSE) | PolyForm Noncommercial: copy/modify for noncommercial use only |

Contact: [rppl@dcsbl.nl](mailto:rppl@dcsbl.nl).

## Handy extras

- Coding agents: read [AGENTS.md](AGENTS.md) before touching session, sync, or HealthKit flow.
- Ultra Action Button: Settings → Action Button → Workout → Rppl (starts a session only).
- Export is raw on purpose: great for Mac analysis, so share deliberately.
- When unsure about product behavior, prefer the locks above over inventing UX.
