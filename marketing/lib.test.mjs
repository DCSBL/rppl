import assert from "node:assert/strict";
import test from "node:test";
import zlib from "node:zlib";
import { parseText, pngInfo, stripAlpha, validateConfig } from "./lib.mjs";

test("parseText marks bold words as accent", () => {
  assert.deepEqual(parseText("TRACK **YOUR** SESSIONS"), [
    { word: "TRACK", accent: false },
    { word: "YOUR", accent: true },
    { word: "SESSIONS", accent: false },
  ]);
  assert.equal(parseText("**A B** C")[1].accent, true);
});

test("parseText rejects empty and unbalanced text", () => {
  assert.throws(() => parseText(" "));
  assert.throws(() => parseText("**YOUR CABLEPARK"));
});

function rgbaPng(w, h, px) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) px.copy(raw, y * (w * 4 + 1) + 1 + x * 4);
  const crc = (b) => { const o = Buffer.alloc(4); o.writeUInt32BE(zlib.crc32(b) >>> 0); return o; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); return Buffer.concat([l, td, crc(td)]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

test("stripAlpha re-encodes RGBA as RGB and keeps size and colour", () => {
  const out = stripAlpha(rgbaPng(3, 2, Buffer.from([10, 20, 30, 255])));
  assert.deepEqual(pngInfo(out), { width: 3, height: 2, bitDepth: 8, colorType: 2 });
  const raw = zlib.inflateSync(out.subarray(out.indexOf("IDAT") + 4, out.indexOf("IEND") - 8));
  assert.deepEqual([...raw.subarray(1, 4)], [10, 20, 30]);
  assert.equal(stripAlpha(out), out);
});

test("validateConfig catches unknown format and duplicate ids", () => {
  const base = { formats: { a: { w: 1, h: 2, folder: "x" } }, slides: [{ id: "s", text: "HI", screenshot: "n", formats: ["a"] }] };
  validateConfig(base);
  assert.throws(() => validateConfig({ ...base, slides: [{ ...base.slides[0], formats: ["zzz"] }] }), /unknown format/);
  assert.throws(() => validateConfig({ ...base, slides: [base.slides[0], base.slides[0]] }), /duplicate/);
});

test("validateConfig header layout needs image and title", () => {
  const base = { formats: { a: { w: 1, h: 1, folder: "a" } }, defaults: { formats: ["a"] } };
  validateConfig({ ...base, slides: [{ id: "h", layout: "header", image: "h.jpg", title: "rppl", tagline: "YOUR **CABLEPARK** BUDDY" }] });
  assert.throws(() => validateConfig({ ...base, slides: [{ id: "h", layout: "header", title: "rppl", tagline: "HI" }] }), /header/);
  assert.throws(() => validateConfig({ ...base, slides: [{ id: "h", layout: "header", image: "h.jpg", title: "rppl" }] }), /text/);
});

test("validateConfig search layout needs image, title, screenshot and watch_screenshot", () => {
  const base = { formats: { a: { w: 1, h: 1, folder: "a" } }, defaults: { formats: ["a"] } };
  const search = { id: "s", layout: "search", image: "s.jpg", title: "rppl", text: "**YOUR** CABLEPARK BUDDY", screenshot: "n", watch_screenshot: "w" };
  validateConfig({ ...base, slides: [search] });
  assert.throws(() => validateConfig({ ...base, slides: [{ ...search, watch_screenshot: undefined }] }), /search/);
});

test("validateConfig duo layout needs text_at and devices with kind, position and a source", () => {
  const base = { formats: { a: { w: 1, h: 1, folder: "a" } }, defaults: { formats: ["a"] } };
  const duo = { id: "d", layout: "duo", text: "FIND **YOUR** SPOTS", text_at: { x: 1, y: 2, size: 3 }, devices: [{ kind: "inner", file: "f.jpg", x: 0, y: 0, w: 10 }] };
  validateConfig({ ...base, slides: [duo] });
  assert.throws(() => validateConfig({ ...base, slides: [{ ...duo, text_at: undefined }] }), /text_at/);
  assert.throws(() => validateConfig({ ...base, slides: [{ ...duo, devices: [] }] }), /devices/);
  assert.throws(() => validateConfig({ ...base, slides: [{ ...duo, devices: [{ kind: "tablet", file: "f.jpg", x: 0, y: 0, w: 1 }] }] }), /kind/);
  assert.throws(() => validateConfig({ ...base, slides: [{ ...duo, devices: [{ kind: "watch", x: 0, y: 0, w: 1 }] }] }), /file or screenshot/);
});
