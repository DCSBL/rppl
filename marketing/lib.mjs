// Pure helpers for render.mjs (no browser), covered by lib.test.mjs.
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

/** "**YOUR** CABLEPARK BUDDY" -> [{word:"YOUR",accent:true},{word:"CABLEPARK"},{word:"BUDDY"}]; one word per line. */
export function parseText(text) {
  if (typeof text !== "string" || !text.trim()) throw new Error("slide text must be a non-empty string");
  const parts = text.split("**");
  if (parts.length % 2 === 0) throw new Error(`unbalanced ** in text: ${text}`);
  const words = [];
  parts.forEach((part, i) => {
    for (const word of part.split(/\s+/).filter(Boolean)) words.push({ word, accent: i % 2 === 1 });
  });
  return words;
}

const MIME = { ".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg" };

/** Find `name` (with or without iphone-/watch- release prefix) under `dirs`. Returns absolute path or null. */
export function findShot(name, dirs) {
  const wanted = new Set();
  for (const prefix of ["", "iphone-", "watch-"]) for (const ext of Object.keys(MIME)) wanted.add(`${prefix}${name}${ext}`);
  const walk = (dir) => {
    if (!fs.existsSync(dir)) return null;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        const hit = walk(full);
        if (hit) return hit;
      } else if (wanted.has(entry.name)) return full;
    }
    return null;
  };
  for (const dir of dirs) {
    const hit = walk(dir);
    if (hit) return hit;
  }
  return null;
}

export function dataUri(file) {
  const mime = MIME[path.extname(file).toLowerCase()];
  if (!mime) throw new Error(`unsupported image type: ${file}`);
  return `data:${mime};base64,${fs.readFileSync(file).toString("base64")}`;
}

/** Resolve a slide's shot name to a file: CI export dirs first, then (optional) committed site fallback. */
export function resolveShot(name, { dirs, fallbacks, allowFallback, root }) {
  const hit = findShot(name, dirs);
  if (hit) return hit;
  const fb = allowFallback && fallbacks?.[name];
  if (fb && fs.existsSync(path.resolve(root, fb))) return path.resolve(root, fb);
  throw new Error(`screenshot "${name}" not found in ${dirs.join(", ")}${allowFallback ? " or fallbacks" : ""}`);
}

// ---- PNG: App Store rejects alpha, Chromium writes RGBA. Re-encode as 8-bit RGB. ----

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, "latin1");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([head.subarray(4), data])) >>> 0, 0);
  return Buffer.concat([head, data, crc]);
}

function readChunks(png) {
  if (!png.subarray(0, 8).equals(SIG)) throw new Error("not a PNG");
  const out = [];
  for (let pos = 8; pos < png.length; ) {
    const len = png.readUInt32BE(pos);
    out.push({ type: png.toString("latin1", pos + 4, pos + 8), data: png.subarray(pos + 8, pos + 8 + len) });
    pos += 12 + len;
  }
  return out;
}

export function pngInfo(png) {
  const ihdr = readChunks(png)[0].data;
  return { width: ihdr.readUInt32BE(0), height: ihdr.readUInt32BE(4), bitDepth: ihdr[8], colorType: ihdr[9] };
}

export function stripAlpha(png) {
  const chunks = readChunks(png);
  const { width, height, bitDepth, colorType } = pngInfo(png);
  if (colorType === 2) return png;
  if (colorType !== 6 || bitDepth !== 8) throw new Error(`unsupported PNG (colorType ${colorType}, depth ${bitDepth})`);
  const raw = zlib.inflateSync(Buffer.concat(chunks.filter((c) => c.type === "IDAT").map((c) => c.data)));
  const stride = width * 4;
  const rgba = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const row = rgba.subarray(y * stride, (y + 1) * stride);
    const prev = y ? rgba.subarray((y - 1) * stride, y * stride) : null;
    for (let i = 0; i < stride; i++) {
      const a = i >= 4 ? row[i - 4] : 0;
      const b = prev ? prev[i] : 0;
      const c = prev && i >= 4 ? prev[i - 4] : 0;
      let add;
      if (filter === 0) add = 0;
      else if (filter === 1) add = a;
      else if (filter === 2) add = b;
      else if (filter === 3) add = (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        add = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else throw new Error(`bad PNG filter ${filter}`);
      row[i] = (src[i] + add) & 255;
    }
  }
  const rgb = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    const o = y * (width * 3 + 1);
    rgb[o] = 0;
    for (let x = 0; x < width; x++) {
      // Backgrounds are opaque; blend defensively against white in case a pixel is not.
      const s = y * stride + x * 4;
      const al = rgba[s + 3] / 255;
      for (let k = 0; k < 3; k++) rgb[o + 1 + x * 3 + k] = Math.round(rgba[s + k] * al + 255 * (1 - al));
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([SIG, chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(rgb, { level: 6 })), chunk("IEND", Buffer.alloc(0))]);
}

/** Validate marketing.yaml shape; throws with a path-like message on the first problem. */
export function validateConfig(cfg) {
  const fail = (m) => { throw new Error(`marketing.yaml: ${m}`); };
  if (!cfg?.formats || typeof cfg.formats !== "object") fail("formats missing");
  for (const [k, f] of Object.entries(cfg.formats)) {
    if (!Number.isInteger(f.w) || !Number.isInteger(f.h) || !f.folder) fail(`formats.${k} needs integer w, h and folder`);
  }
  const defaults = cfg.defaults ?? {};
  if (!Array.isArray(cfg.slides) || !cfg.slides.length) fail("slides must be a non-empty list");
  const ids = new Set();
  cfg.slides.forEach((s, i) => {
    if (!s.id || ids.has(s.id)) fail(`slides[${i}].id missing or duplicate`);
    ids.add(s.id);
    if (s.layout === "header") {
      if (!s.image || !s.title) fail(`slides[${i}] (header) needs image and title`);
      parseText(s.tagline);
    } else if (s.layout === "search") {
      if (!s.image || !s.title || !s.screenshot || !s.watch_screenshot) fail(`slides[${i}] (search) needs image, title, screenshot and watch_screenshot`);
      parseText(s.text);
    } else if (s.layout === "duo") {
      parseText(s.text);
      if (!s.text_at || ![s.text_at.x, s.text_at.y, s.text_at.size].every(Number.isFinite)) fail(`slides[${i}] (duo) needs text_at {x, y, size}`);
      if (s.logo_at && ![s.logo_at.x, s.logo_at.y, s.logo_at.size].every(Number.isFinite)) fail(`slides[${i}].logo_at needs x, y and size`);
      if (!Array.isArray(s.devices) || !s.devices.length) fail(`slides[${i}] (duo) needs devices`);
      s.devices.forEach((d, j) => {
        if (!["outer", "inner", "watch"].includes(d.kind)) fail(`slides[${i}].devices[${j}].kind must be outer|inner|watch`);
        if (![d.x, d.y, d.w].every(Number.isFinite)) fail(`slides[${i}].devices[${j}] needs numeric x, y and w`);
        if (!d.file && !d.screenshot) fail(`slides[${i}].devices[${j}] needs file or screenshot`);
      });
    } else if (s.layout === "usp") {
      if (!Array.isArray(s.items) || !s.items.length) fail(`slides[${i}] (usp) needs items`);
    } else {
      parseText(s.text);
      if (!s.screenshot) fail(`slides[${i}].screenshot missing`);
    }
    for (const f of s.formats ?? defaults.formats ?? []) if (!cfg.formats[f]) fail(`slides[${i}] unknown format ${f}`);
    const align = s.align ?? defaults.align ?? "left";
    if (!["left", "center", "right"].includes(align)) fail(`slides[${i}].align must be left|center|right`);
    if (s.watch && !["left", "right"].includes(s.watch.side ?? "right")) fail(`slides[${i}].watch.side must be left|right`);
  });
}
