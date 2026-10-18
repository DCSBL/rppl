# App Store marketing assets

Stills for the App Store product page, rendered from HTML with the same look as [rppl.nl](https://rppl.nl): Poppins headlines, the site's CSS device frames, the real app screenshots from CI. Everything lives in [`marketing/`](../marketing).

| Output | Sizes | Folder in the zip |
|--------|-------|-------------------|
| iPhone screenshots | 6.9" 1320x2868, 6.5" 1284x2778 | `screenshots/iphone-6.9/`, `screenshots/iphone-6.5/` |
| Product page header | 21:9 3840x1646, 16:9 5244x2950 | `product-page-header/21x9/`, `product-page-header/16x9/` |
| Search results | 3:2 3840x2560, 16:9 5244x2950 | `search-results/3x2/`, `search-results/16x9/` |

Files are `<NN>-<slide id>.png`, numbered in `slides` order. PNGs have no alpha (App Store Connect rejects it); `render.mjs` re-encodes the browser output as RGB. Specs: [screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [header and search results](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications). The 6.9" set is the required one; check the specs page before adding formats.

## What gets rendered: `marketing/marketing.yaml`

```yaml
slides:
  - id: track
    text: "TRACK **YOUR** SESSIONS"   # one word per line, **bold** = accent colour
    align: right                       # text side: left | center | right; devices go to the other side
    screenshot: 04-session-tracked-2   # CI export name, see below
    watch_screenshot: 01-start         # optional
    watch: { side: right, y: 0.7 }     # optional: left | right, vertical position as a fraction of the height, scale
    logo: true                         # optional, small logo above the text
    formats: [iphone-6.9]              # optional, default `defaults.formats`
    background: { top: "#e4e6f0", bottom: "#5f8299" }
  - id: usp
    layout: usp                        # logo, title and icon rows (icons: code, lock-phone, no-dollar)
```

`formats` maps a name to pixel size and output folder; add a format there to render it. Text, alignment, colours and placement are all data, not template code. The template is `template.css` (frames and type) and `layout.js` (placement).

`screenshot` names are the XCUITest attachment names from `RpplScreenshotTests` / `RpplWatchScreenshotTests`, which `release-screenshots.yml` exports (the files are `iphone-<name>.png` / `watch-<name>.png` on the release). A missing name fails the render. Pick shots without Apple Maps imagery where you can.

## Render locally

```sh
cd marketing && npm ci && npx playwright install chromium
node render.mjs --allow-fallback --out /tmp/rppl-assets        # website screenshots as stand-ins
node render.mjs --shots path/to/exported-pngs --out /tmp/rppl-assets --only track --formats iphone-6.9
python3 scripts/ci/check_marketing_assets.py /tmp/rppl-assets  # exact sizes, no alpha, nothing missing
```

`--allow-fallback` uses the committed site screenshots (`fallbacks:` in the YAML) when no CI export is found. The preview is lower resolution than real CI shots.

## When it runs

- **PRs** touching `marketing/`: [`marketing-render.yml`](../.github/workflows/marketing-render.yml) renders with the site screenshots, checks sizes/alpha and uploads `appstore-assets-preview`.
- **Releases**: the `marketing` job of [`release-screenshots.yml`](../.github/workflows/release-screenshots.yml) runs after the screenshots and attaches `rppl-appstore-assets-<tag>.zip` to the release. It only runs for **full releases** (tag without `-beta.N` / `-rc.N`).
- **Manually**: Actions, **Release screenshots**, **Run workflow**: pick the branch (its `marketing/` is used) and enter an existing release tag. The zip is uploaded to that release, also for a beta tag.

The zip is uploaded to App Store Connect by hand.

## Fonts and device frames

Poppins comes from the `@fontsource/poppins` npm package (SIL OFL, notice in [LEGAL.md](../LEGAL.md)); nothing is downloaded when rendering. The frames are generic CSS, like on the website: no Apple logos, no Apple device artwork. Apple publishes its own [marketing resources and guidelines](https://developer.apple.com/app-store/marketing/guidelines/); check them if you add Apple device artwork.
