# App Store text

The fixed App Store text, one folder per App Store Connect locale (same layout as fastlane `deliver`):

| File | App Store Connect field | Limit |
|------|-------------------------|-------|
| `description.txt` | Description | 4000 |
| `promotional_text.txt` | Promotional Text | 170 |
| `keywords.txt` | Keywords (comma separated, no spaces after commas) | 100 |

"What's New" is not here: it is written per release from the merged PRs. See [Docs/Release.md](../../Docs/Release.md#whats-new-in-the-app-store).

When a final release is published, **Release: notes** copies these files into the App Store version (and creates the version when it is missing). Edit the files here, not in App Store Connect: the next release overwrites what is in App Store Connect. Plain text only, no HTML entities.

`en-US` is the source. `nl-NL` was written first; `de-DE` and `fr-FR` were translated with Claude (informal *du* / *tu*, wakeboard slang kept in English, Apple's own term for Health and the Action button) and have not been read by a native speaker yet. A new app language needs a folder here and an entry in `LOCALES` in `scripts/ci/release_notes.py`; the unit test fails until both exist.

Name, subtitle and screenshots are not managed here.
