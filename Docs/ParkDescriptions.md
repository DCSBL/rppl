# Park description tone of voice

How to write the free-text `description` fields in a park YAML file (park-level `description`,
per-cable `description`, `opening.note`) — for any locale, but written with Dutch ("direct-dutch") as
the reference style. Applies whenever an AI agent drafts or rewrites this text, e.g. under the
[`park-data-collection`](../.claude/skills/park-data-collection/SKILL.md) skill. See also the general
[voice and tone rules](DesignLanguage.md#voice-and-tone) and
[wakeboard slang](../AGENTS.md#wakeboard-slang-all-locales) in AGENTS.md, which still apply.

## Rules

1. **No em-dash, en-dash, or a hyphen `-` used as a dash.** Split into two sentences, or use a comma.
   A hyphen is only for compound words (`2.0-kabel`) or a real range (`14:00-20:00`).
2. **State facts, don't sell.** Say what the cable, dock, or feature is or does. No hype words:
   *geweldig*, *fantastisch*, *gaaf*, *uniek*, *ultieme*, and their English equivalents (*amazing*,
   *awesome*, *fantastic*, *ultimate*) are all out.
3. **Direct sentences.** Subject, verb, fact. No warm-up clauses, no filler adjectives.
4. **Short.** One or two sentences per field. If there's more to say, that's a sign the field has too
   much in it, not a reason to write a paragraph.
5. **Wakeboard slang stays English** per [AGENTS.md](../AGENTS.md#wakeboard-slang-all-locales): *kicker*,
   *rail*, *box*, *pop*, *cut in*, *dock*, *set*, *lap*, *session* keep their English form inside Dutch
   sentences. Don't translate them.
6. **Only what's confirmed.** Per the `park-data-collection` skill, don't add a claim (difficulty,
   suitability, atmosphere) that isn't on the source page.

## Examples

| Don't | Do |
|-------|-----|
| Deze gave cable zorgt voor een fantastische ervaring voor beginners en gevorderden. | Deze cable is geschikt voor beginners en gevorderden. |
| Een unieke kicker die zorgt voor de ultieme pop — een must voor iedere rider! | Deze kicker geeft veel pop. |
| Geniet van deze prachtige, sfeervolle dock aan het water. | De dock ligt aan het water. |
| Dit park heeft alles wat je nodig hebt - van rails tot boxes. | Dit park heeft rails en boxes. |

## English descriptions

Same rules: no dash-as-punctuation, no hype adjectives, state the fact plainly.
("This cable suits beginners and advanced riders", not "This amazing cable delivers a fantastic
experience for riders of all levels.")
