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
| Set / pause thresholds | [Docs/RideDetection.md](Docs/RideDetection.md) |
| Xcode, hooks, `make check` | [Docs/DevWorkflow.md](Docs/DevWorkflow.md) |
| UI look, voice and tone | [Docs/DesignLanguage.md](Docs/DesignLanguage.md) |
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
| Detection | Live set / inactive / unsure → `detections.jsonl` · no manual Action Button labels |
| Phone | View-only list / map / Share-Export |
| HealthKit | Save via `finishWorkout()` · `waterSports` · session stays running · set + dock activities · set-scoped energy · ride-gated distance + GPS route · HR/energy mirrored into files |
| Transfer | Phone may be away · WC after Stop · never delete Watch data until phone ack |
| Water Lock | On at session start |
| Identity | Random install-scoped ID (`testerId`) in App Group / UserDefaults · reset on reinstall |
| Core | Pure logic in `RpplCore` · unit-tested with `swift test` |

Export exists so developers can share raw session data for analysis. It is not the main rider-facing story; keep it out of marketing copy unless you are talking about Share-Export deliberately.

Thresholds: [Docs/RideDetection.md](Docs/RideDetection.md).

## Where to start

Pick the area you want to touch, then open its entry point:

| I want to… | Start here |
|------------|------------|
| Change detection (riding / inactive) | `RpplCore/Sources/RpplCore/DetectionEngine.swift`, then [Docs/RideDetection.md](Docs/RideDetection.md). Run `cd RpplCore && swift test`, no device needed. |
| Change session stats (sets, laps, speed) | `SessionStatsBuilder.swift` in `RpplCore`, [RpplCore/DESIGN.md](RpplCore/DESIGN.md) |
| Change the Watch recording loop | `RpplWatch/WatchSessionController.swift` (needs a real Watch) |
| Change the iPhone logbook / export | `Rppl/ContentView.swift`, `Rppl/PhoneConnectivityService.swift` |
| Change copy or translations | the `*.xcstrings` files, and the slang rules in [AGENTS.md](AGENTS.md) |
| Change the website | `web/`, see [web/README.md](web/README.md) (`npm ci && npm run dev`) |

New here? Read [Docs/DESIGN.md](Docs/DESIGN.md) for the big picture, then do the quick start below. Logic in `RpplCore` is the easiest place to begin because it is covered by `swift test` and has no Apple device dependencies.

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

## Ideas and pull requests

Open an issue for bugs or ideas, or a PR with a suggested change. All ideas are welcome; some will fit the project today and some will not. That is fine. I will consider them.

What matters for a change:

1. **Explainable.** You can describe what changed and why, in your own words. AI help is fine; drive-by autonomous PRs are not. Same bar whether you typed every line or vibed it. Inspired by the [Open Home Foundation AI policy](https://developers.home-assistant.io/blog/2026/07/20/ai-policy/).
2. **Documented.** Update the relevant docs when behavior or layout changes (see the reading guide above).
3. **Tested.** Cover it with automated tests where that makes sense (`cd RpplCore && swift test` for Core logic), or say clearly how you tested it by hand on device.

Also keep pre-commit and the push gate green, and keep wakeboard slang authentic in every locale ([AGENTS.md](AGENTS.md)). Small, focused PRs are easier to review.

Adding a package, icon, font or other work that someone else made? Add its copyright and license to "Open-source notices" in [LEGAL.md](LEGAL.md) in the same PR. That section ships in the app.

## Coding agents

Read [AGENTS.md](AGENTS.md) before changing session, sync, or HealthKit flow. When unsure about product behavior, follow the defaults above and stop to ask if a change forks UX.

**PR titles** (not necessarily each commit): `<component>(<type>): <short description>` — e.g. `watch(feat): …`, `slang(fix): …`. Details and component/type tables: [contributions/agent.md](contributions/agent.md).
