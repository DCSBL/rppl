#!/usr/bin/env node
// Render App Store marketing stills from marketing.yaml. See Docs/Marketing.md.
// Usage: node render.mjs --shots DIR [--shots DIR2] --out OUT [--config marketing.yaml]
//                        [--only slide-id,...] [--formats key,...] [--allow-fallback]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright";
import YAML from "yaml";
import { dataUri, parseText, resolveShot, stripAlpha, validateConfig } from "./lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = { shots: [], out: null, config: path.join(here, "marketing.yaml"), only: null, formats: null, allowFallback: false };
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === "--shots") args.shots.push(path.resolve(process.argv[++i]));
  else if (a === "--out") args.out = path.resolve(process.argv[++i]);
  else if (a === "--config") args.config = path.resolve(process.argv[++i]);
  else if (a === "--only") args.only = process.argv[++i].split(",");
  else if (a === "--formats") args.formats = process.argv[++i].split(",");
  else if (a === "--allow-fallback") args.allowFallback = true;
  else throw new Error(`unknown argument ${a}`);
}
if (!args.out) throw new Error("--out required");

const cfg = YAML.parse(fs.readFileSync(args.config, "utf8"));
validateConfig(cfg);
const defaults = { align: "left", background: {}, colors: {}, ...cfg.defaults };
const configDir = path.dirname(args.config);

const fontFile = (weight) => pathToFileURL(path.join(here, "node_modules/@fontsource/poppins/files", `poppins-latin-${weight}-normal.woff2`)).href;
const css = fs.readFileSync(path.join(here, "template.css"), "utf8").replace("%FONT800%", fontFile(800)).replace("%FONT600%", fontFile(600));
const layoutJs = fs.readFileSync(path.join(here, "layout.js"), "utf8");
const logoSvg = fs.readFileSync(path.join(here, "../assets/rppl.svg"), "utf8");

// assets/rppl.svg has four swoosh paths sharing class s0; tint them for the app-icon look or flat colour.
const SWOOSH = ["#b9e3f2", "#4bbfd8", "#1297dd", "#eef5fa"]; // path order of assets/rppl.svg
function logo(colored, flat) {
  let n = 0;
  const body = logoSvg.replace(/<style>[\s\S]*?<\/style>/, "").replace(/class="s0"/g, () => `fill="${colored ? SWOOSH[n++ % 4] : flat}"`);
  return body.replace(/ width="460" height="460"/, "");
}

const ICONS = {
  code: '<path d="M9 8l-4 4 4 4M15 8l4 4-4 4M13 6l-2 12"/>',
  "lock-phone": '<rect x="9" y="3" width="10" height="18" rx="2"/><rect x="3" y="12" width="8" height="6" rx="1" fill="currentColor"/><path d="M5 12v-1.5a2 2 0 014 0V12"/>',
  "no-dollar": '<path d="M15 8.5C14.5 7.5 13.4 7 12 7c-1.7 0-3 .8-3 2 0 3 6 1.5 6 4.500 0 1.200-1.300 2-3 2-1.500 0-2.700-.6-3.200-1.600M12 5v2M12 17v2"/><path d="M5 5l14 14"/>',
};
const icon = (name) => {
  if (!ICONS[name]) throw new Error(`unknown icon ${name}`);
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="11" stroke-width="1.6"/><g transform="translate(3.600 3.600) scale(.7)">${ICONS[name]}</g></svg>`;
};

const shotCtx = { dirs: args.shots, fallbacks: cfg.fallbacks, allowFallback: args.allowFallback, root: configDir };
const shotUri = (name) => dataUri(resolveShot(name, shotCtx));

function html(slide, fmt) {
  const colors = { ...defaults.colors, ...slide.colors };
  const bg = { ...defaults.background, ...slide.background };
  const align = slide.align ?? defaults.align;
  const vars = `--bg-top:${bg.top};--bg-bottom:${bg.bottom};--text:${colors.text};--accent:${colors.accent};--usp:${colors.usp}`;
  const cfgJs = { w: fmt.w, h: fmt.h, layout: slide.layout ?? "shot", align, logo: !!slide.logo, hasWatch: !!slide.watch_screenshot, watch: slide.watch ?? {} };
  let body;
  if (slide.layout === "header") {
    // --u: the lockup scales with the shorter side so it keeps its size from 21:9 to 3:2.
    const u = Math.min(fmt.w, fmt.h * 2.33) / 100;
    return `<!doctype html><html><head><meta charset="utf-8"><style>${css.replaceAll("%W%", fmt.w).replaceAll("%H%", fmt.h)}</style></head>
      <body class="header" style="--u:${u}px"><img class="header-bg" src="${dataUri(path.resolve(configDir, slide.image))}">
      <div class="header-lockup">${logo(true)}<span>${slide.title}</span></div><script>window.CFG=${JSON.stringify({ w: fmt.w, h: fmt.h, layout: "header" })};</script><script>${layoutJs}</script></body></html>`;
  }
  if (slide.layout === "usp") {
    body = `<div id="mark" class="abs logo">${logo(true)}</div><div id="usp-title" class="abs usp-title">${slide.title ?? ""}</div>
      <div id="rows" class="abs">${slide.items.map((it) => `<div class="usp-row">${icon(it.icon)}<span>${it.text}</span></div>`).join("")}</div>`;
  } else {
    const lines = parseText(slide.text).map((l) => `<span${l.accent ? ' class="accent"' : ""}>${l.word}</span>`).join("");
    body = `${slide.logo ? `<div id="logo" class="abs logo">${logo(false, colors.text)}</div>` : ""}
      <h1 id="title" class="abs">${lines}</h1>
      <div id="phone" class="device phone"><img src="${shotUri(slide.screenshot)}"></div>
      ${slide.watch_screenshot ? `<div id="watch" class="device watch"><img src="${shotUri(slide.watch_screenshot)}"></div>` : ""}`;
  }
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css.replaceAll("%W%", fmt.w).replaceAll("%H%", fmt.h)}</style></head>
    <body style="${vars}">${body}<script>window.CFG=${JSON.stringify(cfgJs)};</script><script>${layoutJs}</script></body></html>`;
}

const browser = await chromium.launch();
const tmp = fs.mkdtempSync(path.join(fs.mkdtempSync(path.join(path.resolve(args.out, ".."), ".tmp-")), "p-"));
let count = 0;
try {
  for (const [index, slide] of cfg.slides.entries()) {
    if (args.only && !args.only.includes(slide.id)) continue;
    for (const key of slide.formats ?? defaults.formats) {
      if (args.formats && !args.formats.includes(key)) continue;
      const fmt = cfg.formats[key];
      const file = path.join(tmp, `${slide.id}-${key}.html`);
      fs.writeFileSync(file, html(slide, fmt));
      const page = await browser.newPage({ viewport: { width: fmt.w, height: fmt.h }, deviceScaleFactor: 1 });
      page.on("pageerror", (e) => { throw e; });
      await page.goto(pathToFileURL(file).href);
      await page.waitForFunction("window.__ready === true", null, { timeout: 30000 });
      const png = stripAlpha(await page.screenshot({ type: "png" }));
      await page.close();
      const dir = path.join(args.out, fmt.folder);
      fs.mkdirSync(dir, { recursive: true });
      const name = `${String(index + 1).padStart(2, "0")}-${slide.id}.png`;
      fs.writeFileSync(path.join(dir, name), png);
      console.log(`${fmt.folder}/${name}`);
      count++;
    }
  }
} finally {
  await browser.close();
  fs.rmSync(path.dirname(tmp), { recursive: true, force: true });
}
if (!count) throw new Error("nothing rendered (check --only / --formats)");
