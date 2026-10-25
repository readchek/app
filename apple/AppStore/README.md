# App Store artwork

What's on Chek's App Store page, kept so it can be redone after the screens change.

| Folder | Slot in App Store Connect | Size |
| --- | --- | --- |
| `screenshots/iphone-1206x2622` | iPhone with Dynamic Island, medium phone | 1206 × 2622 |
| `screenshots/iphone-duo-2007x2853` | iPhone Duo | 2007 × 2853 |
| `screenshots/ipad-2064x2752` | iPad 13" | 2064 × 2752 |
| `header-and-search/header-21x9.png` | Product page header | 3840 × 1646 |
| `header-and-search/search-3x2.png` | Search results | 3840 × 2560 |
| `header-and-search/universal-16x9.png` | Either, as one universal asset | 5244 × 2950 |

Every file is a PNG without alpha, as App Store Connect requires.

## Redoing them

The art follows chek.page: its blue, paper and mist, Bricolage headlines with DM Sans text, and the butter speech bubbles. Every book and comic shown is public domain or openly licensed (Project Gutenberg, Pepper&Carrot, StoryWeaver), from the demo server.

1. Make a Release simulator build with the "Sample Library" label hidden and the sample library named "Family Library", without committing that change.
2. `scripts/seed.sh <simulator>` installs it fresh with the books staged where the app carries over Chibi Manga's library, sets the status bar to 9:41, and launches it. Open the sample library, then capture each screen into `raw/<device>/` (`1-home`, `2-comic`, `3-appearance`, `4-library`, `5-shared`, `6-site`, `7-search`).
3. `node scripts/panorama.js <iphone-1206|duo|ipad>` lays each set out as one panorama, so covers and pages cross between slides, and slices it into slides. `node scripts/creative.js` makes the header and search art.

Both scripts use Playwright and read their inputs from `STORE_WORK`: `raw/` for captures, `art/` for covers and comic pages taken from the books, and `brand/` for the fonts from chek.page.
