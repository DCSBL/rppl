# Rppl web

One-pager and privacy page, built with [Astro](https://astro.build) and deployed to GitHub Pages (`https://rppl.nl`, custom domain via `public/CNAME`) by `.github/workflows/web-deploy.yml`.

```bash
cd web
npm ci
npm run dev      # http://localhost:4321/
npm run build    # static output in web/dist
```

- `/privacy/` renders the repo-root `LEGAL.md` at build time (the same file the iOS app bundles). Edit that file, not the page.
- Colors mirror `Rppl/Assets.xcassets` (see `src/styles/global.css`). Keep in sync with [Docs/DesignLanguage.md](../Docs/DesignLanguage.md).
- Screenshots in `public/shots/` must not show Apple Maps imagery. Maps on the site, if added later, use OpenStreetMap with attribution.
- No cookies, no analytics, no third-party requests.
- Pages needs Settings → Pages → Source: GitHub Actions, and a public repo (or a paid plan).

## Custom domain (rppl.nl, TransIP)

DNS at TransIP, for the apex `rppl.nl`. TransIP takes one IP per record, so add each address as its own row (4 A, 4 AAAA) and delete the default parking A record:

| Type | Name | Value |
|------|------|-------|
| A (x4) | `@` | `185.199.108.153`, `.109.153`, `.110.153`, `.111.153` (one record each) |
| AAAA (x4, optional) | `@` | `2606:50c0:8000::153`, `8001::153`, `8002::153`, `8003::153` (one record each; prefix `2606:50c0:`) |
| CNAME | `www` | `dcsbl.github.io.` |

Then Settings → Pages → Custom domain: `rppl.nl`, and enable Enforce HTTPS once the certificate is issued. See the [GitHub docs](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/about-custom-domains-and-github-pages).
