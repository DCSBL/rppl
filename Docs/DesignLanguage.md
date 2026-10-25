# Design language

How Rppl looks and sounds on iPhone and Apple Watch. One visual language, one voice. Plan and rollout: [#226](https://github.com/DCSBL/rppl/issues/226).

The model is Apple Weather: a calm backdrop, translucent tiles, one big number per tile and a small graphic where the data has a shape. Riders glance at it on the dock with wet hands, so every screen has to answer its question in a second.

## Principles

1. **One tile, one question.** "How fast?", "How much riding?". Big number first, graphic second, words last.
2. **Real data only.** A graphic encodes a stat we already have. No decorative numbers, no invented scales.
3. **Native first.** SwiftUI, Swift Charts, `Gauge`, SF Symbols, materials. No third-party UI packages.
4. **Capture beats chrome.** The [north star](../AGENTS.md#product-north-star) stands: UI work never touches session, HealthKit, detection or transfer logic.
5. **Nothing gets lost.** A redesign keeps every action, state and piece of data the screen had.
6. **Smallest complete view.** Reuse an existing building block before adding a new one. No one-off tile, wrapper or style for a single screen. Accessibility (Dynamic Type, VoiceOver labels, chart descriptors) is never the part to cut. See [Code economy](../AGENTS.md#code-economy-adapted-from-ponytail).

## Building blocks

Code lives in `Rppl/Design/`. `DesignGallery.swift` has previews for light, dark and accessibility sizes.

| Piece | Use for |
|-------|---------|
| `RpplBackdrop` / `.rpplBackdrop()` | Background of every top-level tile screen. Forms and editors keep the system grouped background. |
| `InfoTile` | One metric or one topic. Header + content. |
| `InfoTileGrid` | Two columns of tiles, one column at accessibility sizes. Tiles in a row share height. |
| `.rpplTileChrome()` | Tile look on a custom layout (e.g. a full-width row of chips). |
| `MetricValue` | The big number. Splits `"42,2 km/h"` into a large value and a small muted unit (`MetricDisplay.split` in Core). |
| `Gauge` + `.rpplRing(tint:)` | Share of a whole: riding vs inactive. |
| `Gauge` + `.rpplBar(tint:)` | A value against a max: avg vs max speed, sets vs laps. `dot: true` shows the value as a dot on a full-width track (cable speed). |
| `TimelineBar` | Spans on a timeline at their real position and length (sets across a session, `MetricDisplay.span` in Core). Decorative. |
| `StatChip` | Symbol + value (+ caption) in compact rows, like session cards. |
| Swift Charts | Series over time or per set. Always with an accessibility chart descriptor. |

### Tile anatomy

```text
┌────────────────────────────────┐
│ ◉ MAX SPEED                    │  header: metric symbol in its tint + caps label
│ 42,2 km/h                      │  value: MetricValue
│ ▰▰▰▰▰▰▰▰▱▱▱▱                   │  graphic (optional)
│ ◉ 28,5 km/h  Avg speed         │  footnote or chips (optional)
└────────────────────────────────┘
```

- 24 pt continuous corners, 16 pt padding, 12 pt between tiles, 10 pt inside a tile.
- Fill: `.ultraThinMaterial` + `RpplCard` at 60 %. Reduce Transparency draws `RpplCard` solid.
- Hairline: `RpplText` at 8 %.
- Header text is written in sentence case in the string catalog ("Max speed"). The tile uppercases it; VoiceOver reads the original.

### Metrics

Every metric has one symbol and one tint, everywhere: tile header, chip, chart, Watch. The tint colors the symbol and the graphic only; numbers stay in the text color.

| Metric | `MetricKind` | SF Symbol | Tint (asset) |
|--------|--------------|-----------|--------------|
| Distance | `.distance` | `water.waves` | `RpplAccent` |
| Speed | `.speed` | `gauge.with.dots.needle.67percent` | `RpplMetricSpeed` |
| Sets | `.sets` | `flag.checkered` | `RpplMetricSets` |
| Laps | `.laps` | `arrow.triangle.2.circlepath` | `RpplMetricLaps` |
| Duration | `.duration` | `clock` | `RpplMetricTime` |
| Riding | `.riding` | `figure.surfing` (Watch only; iOS uses the MDI `ski-water` glyph via `MetricIcon`) | `RpplMetricRiding` |
| Inactive | `.inactive` | `pause.circle` | `RpplMuted` |
| Water temperature | `.water` | `thermometer.medium` | `RpplMetricWater` |
| Air | `.air` | `cloud.sun` | `RpplMetricAir` |
| Humidity | `.humidity` | `humidity` | `RpplMetricAir` |
| Calories | `.energy` | `flame` | `RpplMetricEnergy` |
| Heart rate | `.heartRate` | `heart.fill` | `RpplMetricEnergy` |
| Park | `.park` | `mappin.and.ellipse` | `RpplAccent` |

All tints reach at least 4.3:1 against light and dark tiles (graphics need 3:1). Check new colors the same way before adding them.

### When to draw a graphic

- A ring or bar only when the proportion means something to a rider (riding share, avg vs max).
- A timeline when *when* and *how long* matter (sets across a session): position and width are real time, never a count.
- A chart when there is a series (per set, over time).
- One number on its own stays a number. Don't chart it.

## Accessibility

- A graphic next to its number as text is decorative: hide it. A graphic without that text gets a label and a value (`Gauge` does this).
- Numbers shrink to 60 % at most, then wrap to a stacked layout at accessibility sizes.
- Text 4.5:1, graphics 3:1, in light and dark.
- Reduce Transparency: solid tiles.
- Increased Contrast: the high-contrast variants of the brand and metric colors in the asset catalogs kick in, and hairlines, ring/bar tracks and tile headers get stronger. Add a high-contrast variant when you add a color asset.
- Reduce Motion: use `withRpplAnimation` / `.rpplAnimation(_:value:)` (`Rppl/Design/RpplMotion.swift`) instead of `withAnimation` / `.animation`.
- Differentiate Without Color: color never carries a state alone. Status dots (sync, park open/closed pins) swap to a symbol, chart series get distinct shapes, cable lines dash.
- Larger Text: see [Larger Text plan](AccessibilityLargerText.md).
- Watch Always On: chrome and supporting metrics dim, the primary metric stays bright.

## Watch

Same metric symbols, tints and header style: `WatchMetric` in `RpplWatch/Views/WatchMetric.swift` mirrors `MetricKind`; keep the two in sync. Metric rows show the symbol in its tint next to the caps caption; the riding view tints its captions (DIST, speed, LAPS). watchOS materials and container backgrounds instead of tiles in tiles. The riding view fits one screen on Ultra without scrolling. Native `Gauge` styles (`.accessoryCircular`) where a ring helps.

## Voice and tone

We talk like a friend who rides: short, direct, a bit of park slang. Never cute, never technical unless you asked for the details.

### Rules

1. **Short.** A label is one or two words. A sentence says one thing.
2. **Sentence case everywhere**: titles, buttons, alerts, tabs. "Delete session?", not "Delete Session?". Proper names keep their capitals: Rppl, Apple Watch, iCloud Drive, Water Lock, Health, Apple Weather.
3. **Talk to the rider.** English "you". Dutch: always *je / jouw*, never *u*. French (Belgium): always *tu / ton*, never *vous*.
4. **Buttons start with a verb**: Export, Delete, Try again, Show example session. Cancel stays Cancel. Dutch buttons use the infinitive, like iOS itself: *Verwijderen*, *Opnieuw proberen*, *Alles selecteren*.
5. **Errors: what happened, then what to do.** "Could not export. Try again from the logbook." No blame, no codes up front, no exclamation marks. Dutch alert titles use *… mislukt* ("Exporteren mislukt"). French alert titles name the thing and say it was impossible ("Export impossible").
6. **App Intent titles are the exception**: Shortcuts and the Action Button follow Apple's Title Case ("Start Cable Park Session").
7. **Empty states: what's missing and how to get it.** "No sessions yet. Record a park day with Apple Watch, or add a session by hand with the + button."
8. **Confirmations:** the question is the title ("Delete session?"), the consequence is the message, the destructive button repeats the verb ("Delete").
9. **Numbers come from the Core formatters** (`DistanceFormat`, `DurationFormat`, `TemperatureFormat`, `EnergyFormat`). Never build units by hand. The locale decides decimal comma and km or mi.
10. **Watch is shorter still.** Buttons at most two words. Metric captions short enough to fit under a number (DIST, LAPS).
11. **Wakeboard slang** follows [AGENTS.md](../AGENTS.md#wakeboard-slang-all-locales): English jargon stays English in every locale.

### One word per thing

| Concept | English | Dutch | Don't use |
|---------|---------|-------|-----------|
| One recording, normally one per park day | session | sessie | workout, ride, rit, session |
| Detected riding segment | set | set | ride, run, lap |
| Full circuit around the cable | lap | lap | round, ronde, set |
| On the water, moving | riding | riding, aan het riden | varen, rijden |
| Recording, not riding | inactive | inactief | paused |
| Product Pause on Watch | paused | gepauzeerd | inactive |
| Cable park | park | park | kabelbaan |

"Park day" explains what a session is (onboarding, empty states). It is not a second name for sessions in lists and headers.

### German

Standard German (`de`) for Germany and German-speaking Belgium. Always the informal *du / dein* form. Buttons follow iOS German: *Löschen*, *Abbrechen*, *Erneut versuchen*, *Auswählen*. Alert titles say what failed ("Export fehlgeschlagen"). Save is *Speichern*, never *Sichern*. Slang stays English per AGENTS.md, including *Session* and *Riding*: *Sets*, *Laps*, *Cable*, *Dock*, *Rider*, *Flags*. Park day is *Parktag*, cable park is *Cable Park*. Obstacle and trick names stay English.

### French (Belgium)

Catalog code `fr`. Address the rider with *tu / ton*. Buttons use the infinitive like iOS (*Supprimer*, *Réessayer*, *Tout sélectionner*); alert titles name the thing and say it was impossible (*Export impossible*). System concepts use Apple's French terms (*Santé*, *Forme*, *Réglages*, *Fichiers*). Slang stays English: *session*, *set*, *lap*, *riding*, *cable*, *dock*, *rider*, trick names, *cable park*, *Water Lock*. Avoid *câble*, *tremplin*, *rampe*, *séance*, *manche*, *tour* for those concepts. A "park day" is a *journée au park*. Booking time slots are *créneaux*.

### Examples

| Before | After |
|--------|-------|
| Delete Session? | Delete session? |
| Could Not Export | Could not export |
| Try Again | Try again |
| Logbook · "Park days and sets" above a list called "Sessions" | Logbook · "Sessions and sets" |
| End Session? | End session? |
