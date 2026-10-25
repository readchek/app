// Renders App Store Connect's creative assets: the product page header
// (21:9), the search result (3:2) and a universal 16:9 for both. The App
// Store lays the icon, name and Get button over the lower part, and crops
// the edges on some devices, so everything that matters stays in the
// middle and the bottom is left to the background.
const { chromium } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const B = __dirname;
// Where the captures (raw/<device>), cover art (art) and brand fonts (brand) live.
const S = process.env.STORE_WORK || path.resolve(B, '..');
const file = p => 'file://' + path.join(S, p);
const C = { blue: '#2448e8', ink: '#171820', paper: '#fafaf7', butter: '#eff3ad' };

const mark = `<svg viewBox="0 0 40 40"><path d="M7 7h11v25H7a4 4 0 0 1-4-4V11a4 4 0 0 1 4-4Zm15 0h11a4 4 0 0 1 4 4v17a4 4 0 0 1-4 4H22Z" fill="${C.paper}"/><path d="m9 19 4 4 7-8 7 8 4-4" fill="none" stroke="${C.blue}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

const phone = (shot, x, y, w, r, z = 3) =>
  `<div class="phone" style="left:${x}h;top:${y}h;width:${w}h;transform:rotate(${r}deg);z-index:${z}"><img src="${file(`raw/iphone/${shot}.png`)}"><i></i></div>`;
const cover = (img, x, y, w, r, z = 2) =>
  `<img class="cover" style="left:${x}h;top:${y}h;width:${w}h;transform:rotate(${r}deg);z-index:${z}" src="${file('art/' + img)}">`;
const card = (img, x, y, w, r, z = 2) =>
  `<div class="card" style="left:${x}h;top:${y}h;width:${w}h;transform:rotate(${r}deg);z-index:${z}"><img src="${file('art/' + img)}"></div>`;
const bubble = (text, x, y, w, h, r, size, z = 6) =>
  `<div class="bubble" style="left:${x}h;top:${y}h;width:${w}h;height:${h}h;font-size:${size}h;transform:rotate(${r}deg);z-index:${z}">${text}</div>`;

// Positions are in h, hundredths of the canvas height, measured from the
// horizontal centre (cx) so one layout reads on every width.
function header(W, H) {
  const cx = W / H * 50;
  // Narrower canvases pull the side pieces in, so they stay on the canvas.
  const k = Math.min(1, cx / 116.6);
  const at = d => cx + d * k;
  return `
    <div class="title" style="left:${cx - 44}h;top:15h;width:88h">
      <div class="brand">${mark}<span>chek</span></div>
      <h1>Just one more chapter.</h1>
    </div>
    ${card('pepper-carrot-episode-10-1.jpg', at(-98) - 4 * (1 - k), 18 + 30 * (1 - k), 30 * (0.6 + 0.4 * k), -9)}
    ${cover('the-secret-garden.jpg', at(-70) - 10 * (1 - k), 30 + 36 * (1 - k), 21 * (0.7 + 0.3 * k), 7)}
    ${cover('alice-s-adventures-in-wonderland.jpg', at(52) + 6 * (1 - k), 26 + 36 * (1 - k), 21 * (0.7 + 0.3 * k), -6)}
    ${card('pepper-carrot-episode-8-1.jpg', at(70) + 8 * (1 - k), 14 + 26 * (1 - k), 30 * (0.6 + 0.4 * k), 8)}
    ${phone('2-comic', cx - 36, 52, 22, -8, 4)}
    ${phone('1-home', cx - 11, 46, 22, 0, 5)}
    ${phone('3-appearance', cx + 14, 52, 22, 8, 4)}
    ${bubble('The world<br>can wait.', cx + 34, 52, 22, 14, -8, 3.6)}
  `;
}

function search(W, H) {
  const cx = W / H * 50;
  return `
    <div class="title" style="left:${cx - 46}h;top:9h;width:92h">
      <div class="brand">${mark}<span>chek</span></div>
      <h1 style="font-size:9.6h">Books and comics,<br>one reader.</h1>
    </div>
    ${cover('the-wonderful-wizard-of-oz.jpg', cx - 58, 46, 17, -10)}
    ${cover('frankenstein.jpg', cx + 41, 44, 17, 9)}
    ${phone('2-comic', cx - 37, 40, 23, -7, 4)}
    ${phone('1-home', cx - 11.5, 36, 23, 0, 5)}
    ${phone('3-appearance', cx + 14, 40, 23, 7, 4)}
  `;
}

const assets = [
  { name: 'header-21x9.png', w: 3840, h: 1646, body: header },
  { name: 'search-3x2.png', w: 3840, h: 2560, body: search },
  { name: 'universal-16x9.png', w: 5244, h: 2950, body: header },
];

const css = (W, H) => {
  const h = H / 100;
  return `
@font-face { font-family: Bricolage; src: url('${file('brand/bricolage-700.ttf')}'); font-weight: 700; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { width: ${W}px; height: ${H}px; position: relative; overflow: hidden; -webkit-font-smoothing: antialiased;
  background: radial-gradient(120h 90h at 50% 30%, #3358ff 0%, ${C.blue} 55%, #1c39c4 100%); color: ${C.paper}; }
/* A darker foot under where the App Store puts the icon and Get button. */
body:after { content: ""; position: absolute; left: 0; right: 0; bottom: 0; height: 34h; z-index: 7;
  background: linear-gradient(to bottom, rgba(16,24,90,0), rgba(16,24,90,.55)); }
.title { position: absolute; text-align: center; z-index: 6; }
.brand { display: inline-flex; align-items: center; gap: 1.4h; font-family: Bricolage; font-weight: 700; font-size: 6.4h; letter-spacing: -.06em; line-height: 1; margin-bottom: 2.2h; }
.brand svg { width: 5.6h; height: 5.6h; }
h1 { font-family: Bricolage; font-weight: 700; font-size: 11h; line-height: .95; letter-spacing: -.05em; }
.phone { position: absolute; padding: .7h; border-radius: 4.2h; background: #111216; box-shadow: 0 0 0 .12h #3a3c44, 0 2h 5h rgba(8,14,60,.45); }
.phone img { display: block; width: 100%; border-radius: 3.6h; }
.phone i { position: absolute; top: 1.4h; left: 50%; transform: translateX(-50%); width: 7h; height: 2h; border-radius: 1.2h; background: #000; }
.cover { position: absolute; border-radius: .5h; box-shadow: 0 2h 5h rgba(8,14,60,.45); }
.card { position: absolute; background: #fff; padding: .7h; box-shadow: 0 2h 5h rgba(8,14,60,.4); }
.card img { display: block; width: 100%; }
.bubble { position: absolute; background: ${C.butter}; color: ${C.ink}; border-radius: 50%; display: flex; align-items: center; justify-content: center; text-align: center; font-family: Bricolage; font-weight: 700; line-height: 1.02; letter-spacing: -.035em; }
.bubble:after { content: ""; position: absolute; left: 6%; top: 8%; border-width: 2h 3.6h 0 0; border-style: solid; border-color: transparent ${C.butter} transparent transparent; transform: rotate(25deg); }
`.replace(/(-?[\d.]+)h\b/g, (_, n) => `${(parseFloat(n) * h).toFixed(1)}px`);
};

(async () => {
  const out = path.join(S, 'creative');
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  for (const a of assets) {
    const h = a.h / 100;
    const body = a.body(a.w, a.h).replace(/(-?[\d.]+)h\b/g, (_, n) => `${(parseFloat(n) * h).toFixed(1)}px`);
    const html = `<!doctype html><html><head><meta charset="utf-8"><style>${css(a.w, a.h)}</style></head><body>${body}</body></html>`;
    const page = await browser.newPage({ viewport: { width: a.w, height: a.h }, deviceScaleFactor: 1 });
    const f = path.join(B, 'creative.html');
    fs.writeFileSync(f, html);
    await page.goto('file://' + f);
    await page.waitForLoadState('networkidle');
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(out, a.name) });
    await page.close();
    console.log(a.name);
  }
  await browser.close();
})();
