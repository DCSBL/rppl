# Contributing to Rppl

Thanks for taking an interest. This file is for people changing the code or docs. Riders who just use the app can stay on [README.md](README.md).

## Reading guide

| Want… | Open |
|-------|------|
| End-user overview | [README.md](README.md) |
| Agent / architecture rules | [AGENTS.md](AGENTS.md) |
| Layers Watch / iPhone / Core | [Docs/DESIGN.md](Docs/DESIGN.md) |
| DetectionEngine UML | [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Streams, HealthKit, transfer, export | [Docs/DataCollection.md](Docs/DataCollection.md) |
| On-disk session layout | [Docs/SessionStorage.md](Docs/SessionStorage.md) |
| Ride / pause thresholds | [Docs/RideDetection.md](Docs/RideDetection.md) |
| Xcode, hooks, `make check` | [Docs/DevWorkflow.md](Docs/DevWorkflow.md) |
| Terms & privacy | [LEGAL.md](LEGAL.md) |

```
RpplCore/     models, IO, DetectionEngine (SPM + Swift Testing)
RpplWatch/    session, sensors, HealthKit, Watch Connectivity send
Rppl/         permissions, sync receive, map, export
Docs/         design and domain docs above
```

## Product defaults

Locked choices for product behavior. Prefer these over inventing UX. Full hard constraints for agents: [AGENTS.md](AGENTS.md).

| | |
|---|---|
| Brand | **Rppl** (capital R; never `RPPL` / `rppl` in user-facing copy) |
| Platforms | iPhone + Watch only · iOS / watchOS **26+** |
| Reference gear | iPhone 16 Pro + Apple Watch Ultra 2 |
| Audience | Riders · reliable capture over flashy UX |
| Session | One `HKWorkoutSession` per park day · Start / Stop on Watch · product Pause allowed (≠ detection `inactive`) |
| Detection | Live ride / inactive / unsure → `detections.jsonl` · no manual Action Button labels |
| Phone | View-only list / map / Share-Export |
| HealthKit | Save via `finishWorkout()` · `waterSports` · session stays running · ride + dock activities · ride-scoped energy · ride-gated distance + GPS route · HR/energy mirrored into files |
| Transfer | Phone may be away · WC after Stop · never delete Watch data until phone ack |
| Water Lock | On at session start |
| Identity | Random install-scoped ID (`testerId`) in App Group / UserDefaults · reset on reinstall |
| Core | Pure logic in `RpplCore` · unit-tested with `swift test` |

Export exists so developers can share raw session data for analysis. It is not the main rider-facing story; keep it out of marketing copy unless you are talking about Share-Export deliberately.

Thresholds: [Docs/RideDetection.md](Docs/RideDetection.md).

## Quick start (dev)

1. Open `Rppl.xcodeproj` in Xcode 26+.
2. Prefer scheme **RpplWatch**, destination **iPhone + Watch**, Cmd+R.
3. Simulator is weak for HealthKit / motion / Watch Connectivity. Use devices.

```bash
brew install pre-commit swiftlint codespell
pre-commit install
make check
```

Details: [Docs/DevWorkflow.md](Docs/DevWorkflow.md).

Bundle IDs (`.dev` builds): `nl.dcsbl.rppl` · Watch `nl.dcsbl.rppl.watchkitapp` · App Group `group.nl.dcsbl.rppl`.

## What we accept

**Fits**

- Fixes that protect capture, sync, ack, or export
- Core logic with tests (`cd RpplCore && swift test`)
- Docs that match reality
- UI only when it helps ride data, not decoration

**Usually does not**

- Cloud sync, accounts, subscriptions
- Trick taxonomy or closed detection enums (codes stay opaque strings)
- Phone-side label editors
- Inventing detector thresholds without measurement

**Quality**

- Prefer pure logic in `RpplCore` so tests run without device APIs
- Pre-commit (hygiene, codespell, SwiftLint) and the push gate must stay green
- Wakeboard slang stays authentic in every locale (see [AGENTS.md](AGENTS.md))

Small, focused pull requests beat kitchen-sink branches.

## AI-assisted contributions

AI tools are welcome. Autonomous drive-by PRs are not. If AI wrote it, you still own it: explain the change in your own words, and run the tests. Same bar whether you typed every line or vibed it.

Inspired by the [Open Home Foundation AI policy](https://developers.home-assistant.io/blog/2026/07/20/ai-policy/).

Test. Test. Test.

## Coding agents

Read [AGENTS.md](AGENTS.md) before changing session, sync, or HealthKit flow. When unsure about product behavior, follow the defaults above and stop to ask if a change forks UX (product pause, phone labeling, deleting Watch data early).
