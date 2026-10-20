# App Store marketing assets

Stills for the App Store product page, rendered from HTML: Poppins headlines, Apple's device frames ([`marketing/device-frames/`](../marketing/device-frames/README.md)), the real app screenshots from CI. Everything lives in [`marketing/`](../marketing).

| Output | Size | Folder in the zip |
|--------|------|-------------------|
| iPhone screenshots | 1206x2622 (the only size we ship; Apple accepts 1206x2622, 2622x1206, 1179x2556 and 2556x1179 for this slot) | `screenshots/iphone-6.3/` |
| Product page header | 16:9 5244x2950 | `product-page-header/16x9/` |
| Search results | 16:9 5244x2950 | `search-results/16x9/` |

The search card on iPhone crops the 16:9 image to about 3:2 (roughly 9% off each side), so the `search` slide keeps everything between x=480 and x=4764. The header is the `header` slide (photo, logo, name and tagline, no devices; Apple crops the header image heavily, so the lockup sits in the uncropped safe area, 1400x962 at (1922, 664) of the 5244x2950 image) and the search results are the `search` slide (photo, logo, headline, phone and watch). Photos live in [`marketing/photos/`](../marketing/photos). Swap one (keep it as large as you can; the 16:9 size needs 5244 px wide) and re-render to change it. The phone and watch frames are scaled to the real size ratio of the devices.

Files are `<NN>-<slide id>.png`, numbered in `slides` order. PNGs have no alpha (App Store Connect rejects it); `render.mjs` re-encodes the browser output as RGB. Specs: [screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [header and search results](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications). Check the specs page before adding formats.

## What gets rendered: `marketing/marketing.yaml`

```yaml
slides:
  - id: track
    text: "TRACK **YOUR** SESSIONS"   # one word per line, **bold** = accent colour
    align: right                       # text side: left | center | right; devices go to the other side
    screenshot: 04-session-tracked-2   # CI export name, see below
    watch_screenshot: 06-live-riding   # optional
    watch: { side: right, y: 0.7 }     # optional: left | right, vertical position as a fraction of the height, scale
    logo: true                         # optional, small logo above the text
    formats: [iphone-6.3]              # optional, default `defaults.formats`
    background: { top: "#e4e6f0", bottom: "#5f8299" }
  - id: header
    layout: header                     # photo + logo + name + tagline, no devices
    image: photos/header.jpg           # relative to marketing.yaml
    title: rppl
    tagline: "YOUR **CABLEPARK** BUDDY"
    formats: [header-16x9]
  - id: search
    layout: search                     # photo + logo + headline + phone and watch
    image: photos/search.jpg
    title: rppl
    text: "**YOUR** CABLEPARK BUDDY"
    screenshot: 04-session-tracked-2
    watch_screenshot: 06-live-riding
    formats: [search-16x9]
  - id: usp
    layout: usp                        # logo, title and icon rows (icons: code, lock-phone, no-euro); `image:` puts them on a photo
```

`formats` maps a name to pixel size and output folder; add a format there to render it. Text, alignment, colours and placement are all data, not template code. The template is `template.css` (frames and type) and `layout.js` (placement). Text lines up with the phone frame: left text with its left edge, right text with its right edge.

`screenshot` names are the XCUITest attachment names from `RpplScreenshotTests` / `RpplWatchScreenshotTests`, which `release-screenshots.yml` exports (the files are `iphone-<name>.png` / `watch-<name>.png` on the release). A missing name fails the render. Pick shots without Apple Maps imagery where you can.

The release run only guarantees the shots the slides use: `screenshots-required` in `release-screenshots.yml` runs just those tests (`testLogbookThreeSessions`, `testTrackedSessionDetail`, `testParksOpen`, Watch `testLiveRiding`) and fails when one of the PNGs is missing. When you point a slide at another shot, add its test to that job's `-only-testing` list and to the check step, and add it to `-skip-testing` in `screenshots-extra`. Everything else runs in `screenshots-extra`, which may fail without blocking marketing.

## Render locally

```sh
cd marketing && npm ci && npx playwright install chromium
node render.mjs --allow-fallback --out /tmp/rppl-assets        # website screenshots as stand-ins
node render.mjs --shots path/to/exported-pngs --out /tmp/rppl-assets --only track --formats iphone-6.3
python3 scripts/ci/check_marketing_assets.py /tmp/rppl-assets  # exact sizes, no alpha, nothing missing
```

`--allow-fallback` uses the committed site screenshots (`fallbacks:` in the YAML) when no CI export is found. The preview is lower resolution than real CI shots.

## When it runs

- **PRs** touching `marketing/`: [`marketing-render.yml`](../.github/workflows/marketing-render.yml) renders with the site screenshots, checks sizes/alpha and uploads `appstore-assets-preview`.
- **Releases**: the `marketing` job of [`release-screenshots.yml`](../.github/workflows/release-screenshots.yml) runs after the screenshots and attaches `rppl-appstore-assets-<tag>.zip` to the release. It runs for every release, betas and release candidates included.
- **Manually**: Actions, **Release screenshots**, **Run workflow**: pick the branch (its `marketing/` is used) and enter an existing release tag. The zip is uploaded to that release, also for a beta tag. By default the simulator screenshots are not made again: the `iphone-*` / `watch-*` assets already on that release are used, so only the marketing job runs (ubuntu, a few minutes). Tick `regenerate_screenshots` to run the simulators first; a release without screenshot assets fails with a message saying so.

The zip is uploaded to App Store Connect by hand.

## Fonts and device frames

Poppins comes from the `@fontsource/poppins` npm package (SIL OFL, notice in [LEGAL.md](../LEGAL.md)); nothing is downloaded when rendering. The frames are generic CSS, like on the website: no Apple logos, no Apple device artwork. Apple publishes its own [marketing resources and guidelines](https://developer.apple.com/app-store/marketing/guidelines/); check them if you add Apple device artwork.
