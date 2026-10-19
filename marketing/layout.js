// Runs in the page. window.CFG = { w, h, layout, align, logo, hasWatch, watch }; places title, logo and devices, sets window.__ready.
// header and search are CSS only (template.css, scaled by --k); shot and usp slides are portrait and placed here.
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
