// Runs in the page. window.CFG = { w, h, layout, align, logo, hasWatch, watch }; places title, logo and devices, sets window.__ready.
// header and search are CSS only (template.css, scaled by --k); shot and usp slides are portrait and placed here (usp also has a landscape variant); duo slides place devices in format pixels.
(async () => {
  const { w: W, h: H, layout, align, logo, hasWatch, watch } = window.CFG;
  const $ = (id) => document.getElementById(id);
  const place = (el, x, y, w, h) => Object.assign(el.style, { left: `${x}px`, top: `${y}px`, ...(w != null && { width: `${w}px` }), ...(h != null && { height: `${h}px` }) });
  await document.fonts.load('800 100px "Poppins"');
  await document.fonts.load('600 100px "Poppins"');
  await Promise.all([...document.images].map((i) => i.decode()));

  if (layout === "header" || layout === "search") {
    window.__ready = true;
    return;
  }

  if (layout === "duo") {
    const { devices, text_at: textAt, logo_at: logoAt, frames } = window.CFG;
    const title = $("title");
    title.style.fontSize = `${textAt.size}px`;
    place(title, textAt.x, textAt.y);
    if (logoAt) place($("logo"), logoAt.x, logoAt.y, logoAt.size, logoAt.size);
    // Outline of a device = everything the border cannot reach through transparent pixels, so the screenshot never pokes out of a rounded corner.
    const outline = (img) => {
      const w = img.naturalWidth, h = img.naturalHeight;
      const c = document.createElement("canvas");
      c.width = w; c.height = h;
      const ctx = c.getContext("2d");
      ctx.drawImage(img, 0, 0);
      const px = ctx.getImageData(0, 0, w, h);
      const outside = new Uint8Array(w * h), stack = new Int32Array(w * h);
      let top = 0;
      const seed = (i) => { if (!outside[i] && px.data[i * 4 + 3] < 200) { outside[i] = 1; stack[top++] = i; } };
      for (let x = 0; x < w; x++) { seed(x); seed((h - 1) * w + x); }
      for (let y = 0; y < h; y++) { seed(y * w); seed(y * w + w - 1); }
      while (top) {
        const i = stack[--top], x = i % w;
        if (x > 0) seed(i - 1);
        if (x < w - 1) seed(i + 1);
        if (i >= w) seed(i - w);
        if (i < w * (h - 1)) seed(i + w);
      }
      for (let i = 0; i < w * h; i++) { px.data[i * 4] = px.data[i * 4 + 1] = px.data[i * 4 + 2] = 255; px.data[i * 4 + 3] = outside[i] ? 0 : 255; }
      ctx.putImageData(px, 0, 0);
      return c;
    };
    const outlines = {};
    for (const [i, d] of devices.entries()) {
      const f = frames[d.kind], frame = $(`frame-${d.kind}`), shot = $(`shot-${i}`);
      outlines[d.kind] ??= outline(frame);
      const s = d.w / f.w, c = $(`dev-${i}`);
      c.width = Math.round(d.w);
      c.height = Math.round(f.h * s);
      place(c, d.x, d.y, c.width, c.height);
      const ctx = c.getContext("2d");
      ctx.imageSmoothingQuality = "high";
      const [ox, oy, ow, oh] = f.opening;
      ctx.drawImage(shot, ox * s, oy * s, ow * s, oh * s);
      ctx.globalCompositeOperation = "destination-in";
      ctx.drawImage(outlines[d.kind], 0, 0, c.width, c.height);
      ctx.globalCompositeOperation = "source-over";
      ctx.drawImage(frame, 0, 0, c.width, c.height);
    }
    window.__ready = true;
    return;
  }

  if (layout === "usp" && W > H) {
    // Landscape (iPhone Duo): proportions of the portrait layout are not usable, so size everything from the height.
    const lh = H * 0.0997;
    place($("mark"), (W - lh) / 2, H * 0.0448, lh, lh);
    const title = $("usp-title");
    title.style.fontSize = `${H * 0.1246}px`;
    place(title, 0, H * 0.1644, W, null);
    title.style.textAlign = "center";
    const rows = $("rows");
    rows.style.fontSize = `${H * 0.0558}px`;
    place(rows, W * 0.1192, H * 0.3936, W * 0.7616, null);
    rows.style.display = "flex";
    rows.style.flexDirection = "column";
    rows.style.gap = `${H * 0.0548}px`;
    window.__ready = true;
    return;
  }

  if (layout === "usp") {
    const rows = $("rows"), mark = $("mark"), title = $("usp-title");
    const lh = W * 0.0966;
    place(mark, (W - lh) / 2, H * 0.041, lh, lh);
    title.style.fontSize = `${W * 0.1208}px`;
    place(title, 0, H * 0.1228, W, null);
    title.style.textAlign = "center";
    rows.style.fontSize = `${W * 0.0531}px`;
    place(rows, W * 0.0886, H * 0.305, W * 0.8228, null);
    rows.style.display = "flex";
    rows.style.flexDirection = "column";
    rows.style.gap = `${H * 0.0558}px`;
    window.__ready = true;
    return;
  }

  const title = $("title"), phone = $("phone");
  const PHONE_AR = 2760 / 1350; // frame PNG aspect ratios (see template.css)
  const WATCH_TO_PHONE = 0.605; // watch frame width / phone frame width = real size ratio
  const WATCH_OVERLAP = 0.66; // share of the watch width that sits over the phone
  const setDevice = (el, w, x, y) => { el.style.setProperty("--w", `${w}px`); place(el, x, y, w); };

  // The text edge lines up with the phone's frame edge: left text = left of the phone, right text = right of the phone.
  let pw = W * 0.725, phoneX = (W - pw) / 2, phoneY = H * 0.335, watchX = 0;
  if (hasWatch) {
    pw = W * 0.797;
    const w2 = pw * WATCH_TO_PHONE, over = w2 * WATCH_OVERLAP;
    const gl = (W - (pw + w2 - over)) / 2;
    const left = watch.side === "left";
    phoneX = left ? gl + w2 - over : gl;
    watchX = left ? gl : gl + pw - over;
    phoneY = H * 0.275;
    setDevice($("watch"), w2, watchX, (watch.y ?? 0.688) * H);
  }
  setDevice(phone, pw, phoneX, phoneY);

  const maxFont = W * 0.1288;
  title.style.fontSize = "100px";
  const textW = pw; // title may use the phone's width
  title.style.fontSize = `${Math.min(maxFont, (100 * textW) / title.scrollWidth)}px`;
  title.style.textAlign = align;
  const x = (width) => (align === "right" ? phoneX + pw - width : align === "center" ? phoneX + (pw - width) / 2 : phoneX);
  let y = H * 0.07;
  if (logo) {
    const lh = W * 0.0966;
    place($("logo"), x(lh), H * 0.037, lh, lh);
    y = H * 0.097;
  }
  place(title, x(title.scrollWidth), y);
  window.__ready = true;
})();
