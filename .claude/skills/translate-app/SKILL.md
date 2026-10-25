---
name: translate-app
description: Add or revise a language in Rppl's string catalogs (.xcstrings). Translates by UI context and local conventions, not word for word, keeps the direct Rppl voice per culture, and guards wakeboard slang. Use for any new locale or copy review.
---

# Translate the app

Adds a locale to the six String Catalogs, or reviews an existing one. No suitable public translate skill existed when this was written (checked the skill directories and the repo), so this encodes Rppl's own rules plus the lessons from the German ([#571](https://github.com/DCSBL/rppl/pull/571)) and French ([#572](https://github.com/DCSBL/rppl/pull/572)) runs.

Source of truth for voice and slang: [Docs/DesignLanguage.md](../../../Docs/DesignLanguage.md#voice-and-tone) and [AGENTS.md](../../../AGENTS.md#wakeboard-slang-all-locales). This skill does not replace them; it says how to apply them to a new language.

## Rules

1. **Research the locale first, then translate.** Before touching a catalog, write down (scratchpad) how the target language and country talk in apps: formal or informal address, how Apple's own iOS strings phrase buttons, alerts and settings in that locale (use Apple's wording for system concepts: Health, Settings, Delete, Cancel), and how direct or polite copy is there. Do not translate English sentence by sentence.
2. **Voice: direct, never flowery, adapted per culture.** The English source is short and plain. Keep that, but let the register follow the country. Examples, to extend per language:
   - Dutch (NL): direct, short, no-nonsense. *je*, infinitive buttons, no softeners.
   - UK English (en-GB, if ever added): same facts, a bit more apologetic ("Sorry, we couldn't export that. Try again from the logbook.") and British spelling and units.
   - German: *du*, plain and compact, iOS-style buttons.
   - French (BE): *tu*, "Export impossible" style alerts, Apple's French terms.
   Never turn directness into rudeness, and never add warmth that makes a label longer. If a culture needs politeness, add it in the sentence, not in labels.
3. **Translate meaning in context, not the word.** The same English word maps to different words by role. Dutch "Free" can be *Gratis* (price), *Vrij* (not occupied) or *Beschikbaar* (available); "Closes" as an opening-hours label differs from "Close" as a button (*Sluit* vs *Sluiten*, *Schließt* vs *Schließen*). Before translating a string:
   - `grep -rn '"<key>"\|<key>' Rppl RpplWatch RpplWidgets RpplCore --include=*.swift` to find where it renders: label, button, title, alert message, accessibility label, App Intent title.
   - Read the `comment` on the catalog entry, the neighbouring strings on that screen, and the existing `nl` and `en` values.
   - Check whether it combines with other text (interpolated `%@`, `%lld`), and whether grammar changes with the value.
   If context still leaves two readings, pick the likelier one and list the string under **Review notes** in the PR. Do not guess silently.
4. **Wakeboard slang stays English** ([AGENTS.md](../../../AGENTS.md#wakeboard-slang-all-locales)): `riding`, `session`, `set`, `lap`, `cable`, `dock`, `kicker`, `feature`, `rail`, `box`, `pop`, `cut in`, `boots`, `bindings`, `regular` / `goofy` / `switch`, `wipeout`, `rider`, and every trick and obstacle name. Do not swap them for literal local words (no *varen*, *rit*, *ronde*, *schans*, *kabelbaan* in Dutch, and the equivalents elsewhere). Check [Nootica's glossary](https://www.nootica.com/webzine/wakeboarding-glossary.html) when unsure. Set (a detected riding segment) and lap (a full circuit) are different things; never use one word for both. Localise the grammar around them (plural, article, declension), not the term. Current state: Dutch uses *sessie* since [#569](https://github.com/DCSBL/rppl/pull/569); German and French keep *Session*/*session*. A new locale keeps the English term unless the user decides otherwise.
5. **Follow the one-word-per-thing table** in DesignLanguage.md and extend it in the same PR with the new locale's column or section.
6. **Numbers and units** come from the Core formatters; never hard-code decimal separators, km vs mi, or date formats in strings. Keep placeholders (`%@`, `%lld`, `%1$@`) identical in count and type, and reorder with positional specifiers when the grammar needs it.
7. **Do not touch other locales.** Existing `en` and `nl` values stay as they are, unless the task is explicitly to revise them.

## Catalogs and workflow

Six catalogs, all with source language `en`: `Rppl/Localizable.xcstrings`, `Rppl/InfoPlist.xcstrings`, `RpplWatch/Localizable.xcstrings`, `RpplWatch/InfoPlist.xcstrings`, `RpplWidgets/Localizable.xcstrings`, `RpplCore/Sources/RpplCore/Resources/Localizable.xcstrings`.

1. **Inventory.** Load each catalog with Python `json`. Take every key that has an `nl` value (or `en` for keys with `extractionState`-free source text) as the live set. Skip `extractionState: stale` entries and entries with no source text.
2. **Translate in batches per catalog**, working from the context found under rule 3. Write the new language's `localizations.<code>.stringUnit` with `"state": "translated"`.
3. **Plurals.** Keys with `variations.plural` need every plural category the target language uses (CLDR): English/Dutch/German have `one` + `other`; French treats 0 and 1 as `one` and needs `many` for large numbers in newer CLDR; Polish, Russian, Arabic have more. Check the CLDR rules for the language, and keep the `%lld` argument.
4. **Locale code.** `fr` vs `fr-BE`: iOS has no separate Belgian French language choice, so a plain `fr` entry serves all French devices. Use a regional code only when wording must diverge. Add the code to `knownRegions` in `Rppl.xcodeproj/project.pbxproj`.
5. **Watch.** Space is tight. Labels and buttons at most two words, captions short enough to sit under a number. German and French strings run 20-40 % longer than English; shorten them (drop articles, use Apple's own short verbs) and flag the longest ones in the PR for an on-device check. Watch strings may deviate from the iPhone wording for length.
6. **Info.plist strings** (permission texts, display names) say what the feature does in the local voice; the app name Rppl and product names (Apple Watch, iCloud Drive, Water Lock, Health) stay unchanged.
7. **Format.** `python3 scripts/format-xcstrings.py --all` (never `json.dumps` defaults, they make whole-file diffs), then `--check --all`.
8. **Verify** with a script, not by eye:
   - every live key has a value for the new code, plural keys have all categories;
   - placeholder multiset equals the English source for every string;
   - `en` and `nl` blocks unchanged vs `HEAD`;
   - no forbidden literal translations of slang terms (grep the output for the anti-pattern words of that language).
9. **Docs.** Add a short voice section for the language to `Docs/DesignLanguage.md` (address form, button style, alert pattern, slang kept, park day / cable park words), as done for German and French.
10. `pre-commit run`. macOS-only checks (build, UI tests) run in CI; say so in the PR.

## PR

- Title: `slang(feat): Add <language> localization` ([contributions/agent.md](../../../contributions/agent.md)). Title, body and docs in English.
- Body follows the repo PR template and states: voice choices, what slang was kept, locale code choice, how many strings per catalog, what was left out (stale, no source) and how it was verified.
- **Review notes:** list the ambiguous strings with the reading chosen, the longest Watch strings, and that no native speaker has reviewed it yet. Ask the user for a native check when one is available.
- App Store copy and marketing slides are not localised in this repo; do not claim they are.
- PR #569 (NL *sessie*) and parallel locale PRs edit the same catalogs. Conflicts are expected; only your own locale blocks should differ, so resolve by keeping both sides.

## Stop and ask the user when

- A term is both slang and a common word and the glossary does not settle it.
- The target country has two plausible registers (formal vs informal, regional variants).
- Source English is itself unclear: report it instead of translating a guess.
