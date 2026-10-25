// Renders the branded App Store set for one device as a single wide
// panorama, then slices it into slides, so pieces can cross from one slide
// into the next. Usage: node panorama.js <iphone|duo|ipad>
const { chromium } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const B = __dirname;
// Where the captures (raw/<device>), cover art (art) and brand fonts (brand) live.
const S = process.env.STORE_WORK || path.resolve(B, '..');
const target = process.argv[2] || 'iphone';
// Other iPhone sizes reuse the iPhone screenshots at App Store Connect's sizes.
const device = target.startsWith('iphone') ? 'iphone' : target;
const sizes = { 'iphone-1290': [1290, 2796], 'iphone-1284': [1284, 2778], 'iphone-1206': [1206, 2622], 'iphone-1179': [1179, 2556] };
const file = p => 'file://' + path.join(S, p);
const art = n => file('art/' + n);
const raw = n => file(`raw/${device}/${n}.png`);

const C = { blue: '#2448e8', ink: '#171820', paper: '#fafaf7', mist: '#eef0f8', butter: '#eff3ad', muted: '#60616d' };

const devices = {
  // w × h canvas; dev: device width (u), top of copy and device (u); island
  // only on iPhone; ratio is the screenshot's height over width.
  iphone: { w: 1320, h: 2868, devW: 74, devTop: 84, copyTop: 14, h1: 13.2, sub: 4.4, radius: 13.5, bezel: 2.3, island: true, ratio: 2868 / 1320 },
  duo:    { w: 2007, h: 2853, devW: 70, devTop: 62, copyTop: 10, h1: 9.6,  sub: 3.2, radius: 6.5,  bezel: 1.6, island: false, ratio: 2853 / 2007 },
  ipad:   { w: 2064, h: 2752, devW: 74, devTop: 54, copyTop: 9,  h1: 8.6,  sub: 2.9, radius: 4.6,  bezel: 1.5, island: false, ratio: 2752 / 2064 },
};
const D = { ...devices[device], ...(sizes[target] ? { w: sizes[target][0], h: sizes[target][1] } : {}) };
const u = D.w / 100;
const tall = device === 'iphone';

// Each slide's background, words, screen and the pieces around it. x and y
// are in u from the slide's top-left, so a piece past 100 lands in the next.
const slides = [
  {
    bg: C.blue, ink: C.paper, sub: 'rgba(250,250,247,.82)', brand: true,
    eyebrow: 'Books. Comics. Me time.',
    h1: 'Just one<br>more chapter.',
    p: 'A reader for books and comics, on your device or your own library server.',
    shot: '1-home', tilt: -5, dx: 6,
    extra: [
      { t: 'card', img: 'pepper-carrot-episode-8-1.jpg', x: 72, y: tall ? 96 : 66, w: 44, r: 9, z: 0 },
      { t: 'bubble', text: 'The world<br>can wait.', x: 3, y: tall ? 172 : 112, w: 40, h: 25, r: -9, size: 6.4 },
    ],
  },
  {
    bg: C.blue, ink: C.paper, sub: 'rgba(250,250,247,.82)',
    h1: 'Comics that<br>fill the screen.',
    p: 'Smooth, full-bleed pages for comics, manga and manhwa.',
    shot: '2-comic', tilt: 0,
    extra: [
      { t: 'card', img: 'pepper-carrot-episode-10-1.jpg', x: 76, y: tall ? 150 : 98, w: 34, r: -7, z: 3 },
      { t: 'pill', text: 'CBZ · CBT · PDF', x: 6, y: tall ? 192 : 130, r: -4, size: 4.2 },
    ],
  },
  {
    bg: C.paper, ink: C.ink, sub: C.muted,
    h1: 'Read your way.',
    p: 'Sepia or dark, any size, the font you like. Your place is always saved.',
    shot: '3-appearance', tilt: 0,
    extra: [
      { t: 'swatches', x: 8, y: tall ? 64 : 46 },
      { t: 'bubble', text: 'Just you<br>and the page.', x: 58, y: tall ? 186 : 120, w: 38, h: 23, r: 7, size: 5.6 },
    ],
  },
  {
    bg: C.mist, ink: C.ink, sub: C.muted,
    h1: 'Every format.<br>One shelf.',
    p: 'Open books from Files, iCloud Drive or any app. No account needed.',
    shot: '4-library', tilt: 0,
    extra: [
      { t: 'pill', text: 'EPUB', x: 2, y: tall ? 112 : 78, r: -8, size: 4.6 },
      { t: 'pill', text: 'PDF', x: 82, y: tall ? 104 : 72, r: 7, size: 4.6 },
      { t: 'pill', text: 'MOBI', x: 76, y: tall ? 152 : 102, r: -5, size: 4.6 },
      { t: 'pill', text: 'FB2', x: 4, y: tall ? 168 : 112, r: 6, size: 4.6 },
      { t: 'cover', img: 'the-wonderful-wizard-of-oz.jpg', x: 88, y: tall ? 186 : 124, w: 26, r: 10, z: 3 },
    ],
  },
  {
    bg: C.blue, ink: C.paper, sub: 'rgba(250,250,247,.82)',
    h1: 'Classics,<br>free to read.',
    p: 'Browse public-domain books right from your Chek library.',
    shot: '6-site', tilt: 0,
    extra: [
      { t: 'cover', img: 'alice-s-adventures-in-wonderland.jpg', x: 79, y: tall ? 132 : 88, w: 24, r: 8, z: 3 },
      { t: 'bubble', text: 'Public<br>domain.', x: 60, y: tall ? 190 : 126, w: 30, h: 19, r: 8, size: 5.6 },
    ],
  },
  {
    bg: C.paper, ink: C.ink, sub: C.muted,
    h1: 'Find it<br>in seconds.',
    p: 'One search across your shelf, shared libraries and sites.',
    shot: '7-search', tilt: 0,
    extra: [
      { t: 'searchpill', text: 'Books, comics, authors', x: 10, y: tall ? 70 : 50 },
      { t: 'cover', img: 'the-secret-garden.jpg', x: 87, y: tall ? 112 : 76, w: 25, r: 9, z: 3 },
    ],
  },
  {
    bg: C.blue, ink: C.paper, sub: 'rgba(250,250,247,.82)',
    h1: 'One library<br>for the family.',
    p: 'Connect your own Chek, Komga or Kavita server, at home or away.',
    shot: '5-shared', tilt: 0,
    extra: [
      { t: 'chip', logo: 'brand/komga-logo.svg', title: 'Komga', note: 'Library server', x: 3, y: tall ? 172 : 114, r: -5 },
      { t: 'chip', logo: 'brand/kavita-logo.svg', title: 'Kavita', note: 'Library server', x: 62, y: tall ? 196 : 130, r: 4 },
    ],
  },
];

const used = slides.filter(s => fs.existsSync(path.join(S, `raw/${device}/${s.shot}.png`)));
const N = used.length;

const mark = (fill, stroke) => `<svg viewBox="0 0 40 40"><path d="M7 7h11v25H7a4 4 0 0 1-4-4V11a4 4 0 0 1 4-4Zm15 0h11a4 4 0 0 1 4 4v17a4 4 0 0 1-4 4H22Z" fill="${fill}"/><path d="m9 19 4 4 7-8 7 8 4-4" fill="none" stroke="${stroke}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

function extra(e, s) {
  const pos = `left:${e.x}u;top:${e.y}u;transform:rotate(${e.r || 0}deg);z-index:${e.z ?? 4}`;
  switch (e.t) {
    case 'card': return `<div class="card" style="${pos};width:${e.w}u"><img src="${art(e.img)}"></div>`;
    case 'cover': return `<img class="cover" style="${pos};width:${e.w}u" src="${art(e.img)}">`;
    case 'bubble': return `<div class="bubble" style="${pos};width:${e.w}u;height:${e.h}u;font-size:${e.size}u">${e.text}</div>`;
    case 'pill': return `<div class="pill" style="${pos};font-size:${e.size}u">${e.text}</div>`;
    case 'chip': return `<div class="chip" style="${pos}"><img src="${file(e.logo)}"><div><b>${e.title}</b><span>${e.note}</span></div></div>`;
    case 'searchpill': return `<div class="search" style="${pos}"><svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg>${e.text}<i></i></div>`;
    case 'swatches': return `<div class="swatches" style="${pos}">${[['#fff', C.ink, 'Light'], ['#f4ecd8', '#4a3a24', 'Sepia'], ['#1b1b1e', '#f2f2f2', 'Dark']].map(([b, f, n], i) => `<div class="sw${i === 1 ? ' on' : ''}"><span style="background:${b};color:${f}">Aa</span></div>`).join('')}</div>`;
  }
  return '';
}

function slide(s, i) {
  const left = i * 100;
  // Shorter canvases pull lower pieces up so nothing falls off the bottom.
  const fy = { iphone: 1, duo: 0.93, ipad: 0.86 }[device];
  // The last slide has nothing after it, so pieces there stay inside.
  const clamp = e => (i === N - 1 && e.w && e.x + e.w > 100 ? { ...e, x: 96 - e.w } : e);
  const pieces = s.extra.map(clamp).map(e => extra({ ...e, x: e.x + left, y: e.y * fy }, s)).join('');
  const shot = raw(s.shot);
  return `
  <section style="left:${left}u;background:${s.bg};color:${s.ink}"></section>
  <div class="copy" style="left:${left}u;color:${s.ink}">
    ${s.brand ? `<div class="brand">${mark(s.ink, s.bg)}<span>chek</span></div>` : ''}
    ${s.eyebrow ? `<div class="eyebrow">${s.eyebrow}</div>` : ''}
    <h1>${s.h1}</h1>
    <p style="color:${s.sub}">${s.p}</p>
  </div>
  <div class="device" style="left:${left + (100 - D.devW) / 2 + (s.dx || 0)}u;top:${D.devTop + (s.brand ? 6 : 0)}u;transform:rotate(${s.tilt}deg)">
    <img src="${shot}">${D.island ? '<i class="island"></i>' : ''}
  </div>
  ${pieces}`;
}

const css = `
@font-face { font-family: Bricolage; src: url('${file('brand/bricolage-700.ttf')}'); font-weight: 700; }
@font-face { font-family: DM; src: url('${file('brand/dm-sans-400.ttf')}'); font-weight: 400; }
@font-face { font-family: DM; src: url('${file('brand/dm-sans-600.ttf')}'); font-weight: 600; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { width: ${N * D.w}px; height: ${D.h}px; position: relative; overflow: hidden; font-family: DM, sans-serif; -webkit-font-smoothing: antialiased; }
section { position: absolute; top: 0; width: 100u; height: ${D.h}px; }
.copy { position: absolute; top: ${D.copyTop}u; width: 100u; padding: 0 8u; z-index: 5; }
.brand { display: flex; align-items: center; gap: 1.6u; font-family: Bricolage; font-weight: 700; font-size: ${D.sub * 1.9}u; letter-spacing: -.06em; line-height: 1; margin-bottom: ${D.sub * 1.6}u; }
.brand svg { width: ${D.sub * 1.7}u; height: ${D.sub * 1.7}u; }
.eyebrow { font-weight: 600; font-size: ${D.sub * 0.95}u; margin-bottom: ${D.sub * 0.7}u; opacity: .9; }
h1 { font-family: Bricolage; font-weight: 700; font-size: ${D.h1}u; line-height: .95; letter-spacing: -.055em; }
p { margin-top: ${D.sub * 0.9}u; font-size: ${D.sub}u; line-height: 1.35; max-width: ${tall ? 80 : 70}u; }
.device { position: absolute; width: ${D.devW}u; padding: ${D.bezel}u; border-radius: ${D.radius}u; background: #111216; z-index: 2;
  box-shadow: 0 0 0 .35u #3a3c44, 0 4u 10u rgba(10,16,60,.35), 0 1u 2u rgba(0,0,0,.25); }
.device img { display: block; width: 100%; border-radius: ${D.radius - D.bezel}u; }
.island { position: absolute; top: ${D.bezel + 2.2}u; left: 50%; transform: translateX(-50%); width: 24u; height: 7u; border-radius: 4u; background: #000; }
.card { position: absolute; background: #fff; padding: 1.4u; box-shadow: 0 3u 7u rgba(10,16,60,.3); }
.card img { display: block; width: 100%; }
.cover { position: absolute; border-radius: .9u; box-shadow: 0 3u 7u rgba(10,16,60,.35), 0 0 0 .15u rgba(0,0,0,.1); }
.bubble { position: absolute; background: ${C.butter}; color: ${C.ink}; border-radius: 50%; display: flex; align-items: center; justify-content: center; text-align: center; font-family: Bricolage; font-weight: 700; line-height: 1.02; letter-spacing: -.035em; }
.bubble:after { content: ""; position: absolute; right: 4%; top: 10%; border-width: 3.4u 0 0 6.6u; border-style: solid; border-color: transparent transparent transparent ${C.butter}; transform: rotate(-27deg); }
.pill { position: absolute; background: #fff; color: ${C.ink}; border: .45u solid ${C.ink}; border-radius: 1.6u; padding: 1.2u 3u; font-family: Bricolage; font-weight: 700; letter-spacing: -.02em; box-shadow: 1.4u 1.2u 0 ${C.butter}; white-space: nowrap; }
.chip { position: absolute; display: flex; align-items: center; gap: 2.4u; background: #fff; color: ${C.ink}; border-radius: 2.6u; padding: 2.2u 4u 2.2u 2.4u; box-shadow: 0 3u 7u rgba(10,16,60,.3); }
.chip img { width: 9u; height: 9u; }
.chip b { display: block; font-weight: 600; font-size: 4.2u; }
.chip span { display: block; font-size: 3u; color: ${C.muted}; }
.search { position: absolute; display: flex; align-items: center; gap: 2u; background: #fff; border: .45u solid ${C.ink}; border-radius: 99u; padding: 2u 4.4u; font-size: 4.4u; font-weight: 600; color: ${C.ink}; box-shadow: 1.4u 1.2u 0 ${C.butter}; }
.search svg { width: 5u; height: 5u; fill: none; stroke: ${C.blue}; stroke-width: 2.6; stroke-linecap: round; }
.search i { width: .4u; height: 5u; background: ${C.blue}; }
.swatches { position: absolute; display: flex; gap: 4u; }
.sw { display: flex; flex-direction: column; align-items: center; gap: 1.2u; font-size: 3u; font-weight: 600; color: ${C.muted}; }
.sw span { width: 12u; height: 12u; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-family: Georgia, serif; font-size: 5u; box-shadow: 0 .8u 2u rgba(0,0,0,.15), 0 0 0 .2u rgba(0,0,0,.08); }
.sw.on span { box-shadow: 0 0 0 .7u ${C.blue}, 0 .8u 2u rgba(0,0,0,.15); }
.sw.on { color: ${C.ink}; }
`.replace(/(-?[\d.]+)u\b/g, (_, n) => `${(parseFloat(n) * u).toFixed(1)}px`);

const html = `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>${used.map(slide).join('').replace(/(-?[\d.]+)u\b/g, (_, n) => `${(parseFloat(n) * u).toFixed(1)}px`)}</body></html>`;

(async () => {
  const out = path.join(S, 'brand-final', target);
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });
  const page_ = path.join(B, `panorama-${target}.html`);
  fs.writeFileSync(page_, html);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: N * D.w, height: D.h }, deviceScaleFactor: 1 });
  await page.goto('file://' + page_);
  await page.waitForLoadState('networkidle');
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(S, `panorama-${target}.png`) });
  for (let i = 0; i < N; i++) {
    const name = `${String(i + 1).padStart(2, '0')}-${used[i].shot.replace(/^\d+-/, '')}.png`;
    await page.screenshot({ path: path.join(out, name), clip: { x: i * D.w, y: 0, width: D.w, height: D.h } });
    console.log(device, name);
  }
  await browser.close();
})();
