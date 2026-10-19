# Device frames

Apple device frames used to render the App Store marketing stills in [`marketing/`](..). See [Docs/Marketing.md](../../Docs/Marketing.md) for the pipeline.

| File | Frame | Screen opening (px) |
|------|-------|---------------------|
| `iPhone 18 Pro - Black - Portrait.png` | iPhone 18 Pro, black, portrait | 1206 x 2622 at (72, 69) in a 1350 x 2760 image |
| `AW Ultra 3 - Black - Ocean Band Black.png` | Apple Watch Ultra 3, black, Ocean Band | 422 x 514 at (89, 223) in a 600 x 960 image |

The screen openings are transparent. A screenshot is placed behind the frame, so its size must match the opening: iPhone screenshots are scaled to the phone opening, Watch screenshots (422 x 514) fit the watch opening exactly.

## Source

Both PNGs come from the Apple Design Resources at <https://developer.apple.com/design/resources/> (product bezels for iPhone and Apple Watch). They are committed unmodified, together with the license that came with the download: [`Apple Design Resources License.rtf`](<Apple Design Resources License.rtf>).

## Why they are committed

The marketing render runs in CI (see [Docs/Marketing.md](../../Docs/Marketing.md#when-it-runs)), where the frames cannot be downloaded interactively because Apple asks you to accept the license first. Keeping them in the repo makes the render reproducible.

## Use

Use these frames only to generate the Rppl App Store marketing stills (screenshots, product page header, search results). Do not use them for anything else, do not embed them in the apps, and do not redistribute or repackage them as standalone assets.

Apple's license covers mock-ups of interfaces for software on Apple platforms and restricts using the resources as general artwork or distributed content. Whether App Store marketing images fall inside that grant is a call the project owner made on purpose; this repository carries the frames on that basis. If Apple objects, or Apple publishes separate marketing assets with different terms, remove the frames and re-render.
