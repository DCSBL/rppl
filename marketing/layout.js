// Runs in the page. window.CFG = { w, h, slide, align, ... }; places title, logo and devices, sets window.__ready.
(async () => {
  const { w: W, h: H, layout, align, logo, hasWatch, watch } = window.CFG;
  const $ = (id) => document.getElementById(id);
  const portrait = H > W;
  const place = (el, x, y, w, h) => Object.assign(el.style, { left: `${x}px`, top: `${y}px`, ...(w != null && { width: `${w}px` }), ...(h != null && { height: `${h}px` }) });
  await document.fonts.load('800 100px "Poppins"');
  await document.fonts.load('600 100px "Poppins"');
  await Promise.all([...document.images].map((i) => i.decode()));

  // Shrink/grow text so its widest line fits `maxW` and the block fits `maxH`.
  const fit = (el, maxW, maxH, lineH) => {
    el.style.fontSize = "100px";
    const k = Math.min(maxW / el.scrollWidth, maxH / el.scrollHeight);
    el.style.fontSize = `${100 * k}px`;
    return k;
  };
  const alignX = (el, left, right, w) => (align === "right" ? right - w : align === "center" ? (left + right - w) / 2 : left);

  if (layout === "usp") {
    const rows = $("rows"), mark = $("mark"), title = $("usp-title");
    const gap = portrait ? H * 0.02 : H * 0.03;
    if (portrait) {
      const lh = H * 0.1;
      place(mark, (W - lh * 1.0) / 2, H * 0.085, lh, lh);
      title.style.fontSize = `${W * 0.1}px`;
      place(title, 0, H * 0.085 + lh + gap, W, null);
      title.style.textAlign = "center";
      rows.style.fontSize = `${W * 0.056}px`;
      place(rows, W * 0.06, H * 0.40, W * 0.88, null);
      rows.style.display = "flex"; rows.style.flexDirection = "column"; rows.style.gap = `${H * 0.075}px`;
    } else {
      const lh = H * 0.3;
      place(mark, W * 0.12, (H - lh * 1.55) / 2, lh, lh);
      title.style.fontSize = `${H * 0.13}px`;
      place(title, W * 0.12 - lh * 0.25, (H - lh * 1.55) / 2 + lh + H * 0.03, lh * 1.5, null);
      title.style.textAlign = "center";
      rows.style.fontSize = `${H * 0.052}px`;
      place(rows, W * 0.46, 0, W * 0.48, null);
      rows.style.display = "flex"; rows.style.flexDirection = "column"; rows.style.gap = `${H * 0.09}px`;
      rows.style.top = `${(H - rows.scrollHeight) / 2}px`;
    }
    window.__ready = true;
    return;
  }

  const title = $("title"), phone = $("phone"), phoneImg = phone.querySelector("img");
  const ar = phoneImg.naturalHeight / phoneImg.naturalWidth;
  const setDevice = (el, w, base) => { el.style.setProperty("--s", w / base); el.style.width = `${w}px`; };
  const wImg = hasWatch ? $("watch").querySelector("img") : null;
  const watchW = (pw) => pw * 0.525 * (watch.scale ?? 1);
  let y;

  if (portrait) {
    const mx = W * 0.13;
    y = H * 0.065;
    if (logo) {
      const lh = H * 0.05;
      place($("logo"), alignX($("logo"), mx, W - mx, lh), y, lh, lh);
      y += lh + H * 0.03;
    }
    fit(title, W - 2 * mx, H * 0.27);
    title.style.textAlign = align;
    place(title, alignX(title, mx, W - mx, title.scrollWidth), y);
    const pw = W * 0.8;
    setDevice(phone, pw, 260);
    place(phone, (W - pw) / 2, y + title.scrollHeight + H * 0.04);
    if (hasWatch) {
      const ww = watchW(pw);
      setDevice($("watch"), ww, 190);
      place($("watch"), watch.side === "left" ? W * 0.04 : W - W * 0.04 - ww, (watch.y ?? 0.7) * H);
    }
  } else {
    const mx = W * 0.07;
    const textLeft = align === "right" ? W * 0.55 : mx;
    const textRight = align === "right" ? W - mx : W * 0.46;
    const lh = H * 0.1;
    const maxTitleH = H * 0.6 - (logo ? lh + H * 0.04 : 0);
    fit(title, textRight - textLeft, maxTitleH);
    title.style.textAlign = align === "center" ? "center" : align;
    const block = title.scrollHeight + (logo ? lh + H * 0.04 : 0);
    y = (H - block) / 2;
    if (logo) {
      place($("logo"), align === "right" ? textRight - lh : align === "center" ? (textLeft + textRight - lh) / 2 : textLeft, y, lh, lh);
      y += lh + H * 0.04;
    }
    place(title, align === "right" ? textRight - title.scrollWidth : align === "center" ? (textLeft + textRight - title.scrollWidth) / 2 : textLeft, y);
    const pw = H * 0.64, ww = hasWatch ? watchW(pw) : 0;
    const groupW = pw + ww * 0.65;
    const cx = align === "right" ? W * 0.27 : W * 0.72;
    const gl = cx - groupW / 2;
    const watchLeft = watch.side === "left";
    setDevice(phone, pw, 260);
    place(phone, watchLeft ? gl + ww * 0.65 : gl, H * 0.1);
    if (hasWatch) {
      setDevice($("watch"), ww, 190);
      place($("watch"), watchLeft ? gl : gl + pw - ww * 0.35, (watch.y ?? 0.5) * H);
    }
  }
  window.__ready = true;
})();
