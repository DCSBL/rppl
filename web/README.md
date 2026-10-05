# Rppl web

One-pager and privacy page, built with [Astro](https://astro.build) and deployed to GitHub Pages (`https://dcsbl.github.io/rppl/`) by `.github/workflows/web-deploy.yml`.

```bash
cd web
npm ci
npm run dev      # http://localhost:4321/rppl/
npm run build    # static output in web/dist
```

- `/privacy/` renders the repo-root `LEGAL.md` at build time (the same file the iOS app bundles). Edit that file, not the page.
- Colors mirror `Rppl/Assets.xcassets` (see `src/styles/global.css`). Keep in sync with [Docs/DesignLanguage.md](../Docs/DesignLanguage.md).
- Screenshots in `public/shots/` must not show Apple Maps imagery. Maps on the site, if added later, use OpenStreetMap with attribution.
- No cookies, no analytics, no third-party requests.
- Pages needs Settings → Pages → Source: GitHub Actions, and a public repo (or a paid plan).
