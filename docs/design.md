# Visual design

How Chek's screens look, so that every screen is built from the same few parts and reads like one of Apple's own. Companion to [language.md](language.md), which owns the words. Rules cite the Human Interface Guidelines (`hig:/layout` means `developer.apple.com/design/human-interface-guidelines/layout`). Reference apps: Books, Music, Podcasts, and Panels.

The one idea: **the system draws the chrome, Chek draws covers.** Bars, tabs, sheets, lists, section headers in lists, empty states, spinners, menus, and buttons are the system's, unstyled. The only custom drawing is a cover, a caption under it, and a shelf of them. Nothing is a card, nothing is tinted for decoration, and no control is glass except the ones the system makes glass. (`hig:/materials`, "Don't use Liquid Glass in the content layer"; `hig:/layout`, "Differentiate controls from content")

## Metrics

Named values in `Metrics` (`apple/Chek/Components/PublicationViews.swift`). Every number on a screen is one of these or a system default.

| Name | Value | Used for |
|---|---|---|
| `margin` | 20 | Leading and trailing edge of all scrolling content, shelf content margins, and the inset of headers. Matches `List` row insets, so rows, shelves, and grids share one left edge. |
| `coverSpacing` | 12 | Between covers, in shelves and grids alike. |
| `gridRowSpacing` | 20 | Between rows of a grid. |
| `sectionSpacing` | 28 | Between shelves on a shelf page, header to header. A shelf row's insets are 12 above and 16 below, so the sum holds. |
| `captionSpacing` | 6 | Cover to its caption. Within the caption, 2. |
| `gridColumns` | 3 on iPhone (`adaptive(minimum: 100, maximum: 150)`), `adaptive(minimum: 140, maximum: 190)` on iPad | Grids. |
| `shelfColumns` | 3 on iPhone, 5 on iPad | A shelf cell is a `containerRelativeFrame` of this many across, less `coverSpacing`, so a cover is the same size on a shelf as in a grid and Home, a library's screen, and a collection agree. `shelfCell()` applies it. |
| `featuredCoverWidth` | 150 iPhone, 200 iPad | Continue Reading only. |
| `rowCoverWidth`, `rowCoverRadius` | 44, 4 | Covers in list rows, with tighter corners so a small cover doesn't look like a pill. |
| `headerCoverWidth` | 110 iPhone, 140 iPad | The cover in a series header. |
| Cover radius | 6 (`CoverView` default), 4 in rows, 3 in the Now Reading bar | Cover corners, scaled with the cover. |

Covers are always 2:3, filled and clipped, with a quiet shadow (`black 18 %`, radius 4, y 2) and a 0.5-pt hairline. A missing cover is a neutral stand-in: `.quaternary` fill with the title in `.footnote` secondary, never a hue from the title. Colorful placeholders read as fake content.

Hit regions are at least 44 × 44 pt (`hig:/buttons`).

## Typography

System text styles only, so Dynamic Type works (`hig:/typography`, "Consider using the built-in text styles"). Weights are regular, medium, semibold, or bold; nothing lighter.

| Role | Style | Where |
|---|---|---|
| Page title | system navigation title | Every screen. Large at tab roots and on a shared library's own screen; inline deeper. See Navigation. |
| Shelf header | `.title2.bold` (`SectionHeader`) | Headers on shelf pages, over shelves and over the rows under them, as in Books and Music. When it leads somewhere, a `chevron.forward` in `.body.semibold` secondary follows it, smaller than the title, as in Music. |
| List section header | system `Section` header | List pages. |
| Series title (header) | `.title2.bold`, up to 3 lines | Series and collection series screens. |
| Row title | `.body` | List rows. |
| Row subtitle | `.subheadline` secondary | Author, series, user name. |
| Cover caption title | `.footnote`, regular, primary, up to 2 lines, no reserved space | Under every cover in a grid or shelf. One weight everywhere (today semibold, medium, and regular are mixed). |
| Cover caption detail | `.caption` secondary | Author or series, chapter, count, or progress. One line. |
| Status | `.caption` secondary; `.caption` tint only for a count of new chapters | "42%", "Finished", "3 new chapters" (`ReadingStatus.caption`). Unopened items show nothing: "New" on every cover in Recently Added is noise. |
| Notice | `.footnote` secondary with a symbol | A refresh that failed over cached content. |
| Reader bar title | `.headline` with a `.caption` secondary chapter | The reader's top bar. |

At accessibility text sizes, covers keep their width and captions take their two lines; headers and buttons wrap. Side-by-side buttons stack (`hig:/typography`, "Consider adjusting your layout at large font sizes").

## Color and tint

- One accent, the system's default, applied by the system to interactive things: buttons, links, selected tab, pickers, the row symbols in navigation lists (as in Books' library list). Nothing else is tinted. (`hig:/color`, "Apply color sparingly")
- Text is `.primary`, `.secondary`, and `.tertiary` only. Red for destructive actions and inline form errors; no orange, yellow, or green anywhere. "Signed Out" under a library's name is secondary text; the words carry it.
- Backgrounds are the system's: `systemBackground` for pages, grouped backgrounds for forms. No fills behind content and no cards around content. Only forms and settings (which are system `Form`s) have inset grouped rows.
- Glass is the system's bars, tab bar, and the reader's floating controls. Custom `glassEffect` is used in one place, the reader's title capsule over comic pages, because the page runs under the bar. (`hig:/materials`, "Use Liquid Glass effects sparingly")
- The Sample Library banner is a `.caption` label on a `.fill.tertiary` capsule, secondary text, no control: it says what's connected and nothing more. Closing the sample is in the library's More menu and in Settings.

Both appearances come free from system colors; no screen names a color.

## Symbols

SF Symbols, default rendering, at the text size they sit beside (`hig:/sf-symbols`). One symbol per idea, everywhere:

| Idea | Symbol |
|---|---|
| Home | `house` (tab) |
| Library, a collection | `books.vertical` |
| Shared (tab), and its empty state | `person.2` |
| A shared library | `building.columns` |
| Sample Library | `sparkles` |
| A site | `globe` |
| Add | `plus` |
| More | `ellipsis` |
| Edit or manage | `pencil` |
| Settings | `gearshape` |
| Contents | `list.bullet` |
| Appearance | `textformat.size` (books), `slider.horizontal.3` (comics) |
| Download, downloaded | `arrow.down.circle`, `arrow.down.circle.fill` |
| Finished, unread | `checkmark.circle`, `circle` |
| Following | `checkmark` (following), `plus` (follow) |
| Failed to load | `wifi.exclamationmark` |
| Signed out | `person.crop.circle.badge.exclamationmark` |
| Search, no results | `magnifyingglass` |
| Delete, remove | `trash` |

Symbols inside list rows go through `Label`, which sizes and aligns them. Symbols in headers and captions are never larger than the text next to them.

## Page types

Six kinds of screen. Every screen is one of them, and a new screen picks one before it's written.

| Type | Built from | Screens |
|---|---|---|
| **Shelf page** | A plain `List`. Each shelf (`CoverShelf`, or `Shelf` for publications) is one row, `shelfRow()`: no separator, a `SectionHeader` at `margin`, then a horizontal `ScrollView` of cells with `contentMargins(margin)`, snapping to covers. Navigation rows (collections, sites) are ordinary `List` rows with a `Label` and the system chevron, under a `SectionHeader` row (`headerRow()`), so nothing pins while scrolling. On Home, every shared library and every site has a shelf headed by its name, leading to its screen. | Home, a shared library's screen |
| **Grid page** | A `ScrollView` of `LazyVGrid(gridColumns, spacing: gridRowSpacing)`, cells top-aligned, padded `margin` and 8 vertically. A search field in the bar drawer when the page is a collection or site. | Library (grid), a collection, a site, a site's search |
| **List page** | A plain `List` of `PublicationRow` or `Label` rows; system section headers. | Library (list), Shared, Search results, Updates, Sites, Advanced, a series' books, a series' chapters (under a series header row) |
| **Form** | A system `Form` (inset grouped), system labels and footers. | Settings and its subscreens, Add Shared Library, Sign In, Add Repository |
| **Sheet** | A `NavigationStack` with an inline title; `xmark` leading, the confirming text button trailing (see language.md, "Sheet toolbars"). Forms and reader panels are sheets. | Settings, Add Shared Library, Sign In, Add Repository, Contents, Appearance |
| **Reader** | Full screen; the system navigation bar and bottom bar with transparent backgrounds, so only the glass controls float. Panels are sheets at `.medium` and `.large` detents. | The reader |

A series screen is a list page whose first row is the series header: cover at `headerCoverWidth` on the leading side, title and details top-aligned beside it, then one row of equal-width capsule buttons at the regular size, at most 360 pt wide together: the reading one `.borderedProminent`, Follow or Download `.bordered`. No separators above or below the header. Tags are a row of `.caption` capsules filled `.quaternary`; the summary is `.subheadline` with a tinted "More" after three lines. Chapter rows carry their date in `.subheadline` secondary, as Podcasts dates episodes; a series' books carry their page count.

## Navigation

- Tab roots (Home, Library, Shared, Search) and a shared library's own screen use large titles. Everything pushed deeper is inline: a collection, a site, Sites, Advanced, Updates, and every Settings subscreen. (`hig:/toolbars`, "Use a large title to help people stay oriented")
- A series screen's title is inline and hidden while its header is on screen, as Music does for an album.
- Sheets are inline.
- Screen toolbars hold at most two items a side: `plus` and the More `ellipsis` menu trailing, Edit or Cancel leading. The system groups them.
- The tab bar is the system's, with the search tab, minimizing on scroll, and the Now Reading bar as its accessory. Only the Home tab carries a badge, for new chapters.

## States

Every screen has the same five states, built from four components and nothing else:

- `EmptyState`: a 48-pt secondary symbol and one sentence in secondary body text, centered. No title, since the screen's own title says where you are, and no buttons: what you can do is part of the sentence as links ("[Add books](chek-action://add) and comics from Files…"), each link's host naming an action. This holds for every screen, the first one included.
- `FailureState` (`EmptyState` with `wifi.exclamationmark` and the error's explanation, with "try again" linked: the words already in it, else added at the end).
- `LoadingState`: a centered system `ProgressView()` at the default size, after 300 ms so quick loads never flash it; at the foot of a paging list, the same spinner in a row. Never `.large`, never captioned. (`hig:/progress-indicators`, "Avoid labeling a spinning progress indicator")
- `StaleNotice`: a `.footnote` secondary `Label` with `wifi.exclamationmark` as the first row of a page that still shows what loaded before.

Offline is a failure like any other ("Check your internet connection and try again.") and is never a separate screen. Signed out is an `EmptyState` with the signed-out symbol: "[Sign in](…) to Home to keep reading." Content kept on the device (downloads) shows under the state, not instead of it.

| Screen | Empty | Loading | Failed, nothing cached | Failed or offline, cached | Signed out |
|---|---|---|---|---|---|
| Home | First screen (below); with only shared libraries and nothing read: a shelf per library and per site | Shelves from the last snapshot; no spinner | Last snapshot; nothing to say here, each library's screen says it | Same | `EmptyState` "Signed Out" with Sign In when every library is signed out and nothing else is here; otherwise a signed-out library's shelves are left out |
| Library | `EmptyState` "No Books" + Add Books; filtered: "No Comics" / "No Finished Books" with no button | — | — | — | — |
| Shared | `EmptyState` "No Shared Libraries" + Add Shared Library, Open Sample Library under it | — | — | — | Row subtitle "Signed Out" |
| A shared library | Shelves absent; Collections section with the one-line explanation; Sites section with Add Sites | `LoadingState` | `FailureState` + Try Again | `StaleNotice` above the last snapshot | `EmptyState` "Signed Out" + Sign In, then the Downloaded shelf if any |
| A collection, a site | `EmptyState` "No Books" / "No Series", no button | `LoadingState`; paging spinner at the foot | `FailureState` + Try Again | `StaleNotice` above the last page; a site shows its Downloaded shelf first | Handled by the library screen; the push is a `FailureState` "Signed Out" + Sign In |
| A series (either kind) | Header, then `EmptyState` "No Chapters" / "No Books" as a row | `LoadingState` | `FailureState` + Try Again | `StaleNotice` row above the header; chapters from the kept listing | As a collection |
| Sites, Advanced | `EmptyState` "No Sites" as a row | `LoadingState` | `FailureState` + Try Again | — | As a collection |
| Search | Idle: nothing under the field (as Books); no results: `ContentUnavailableView.search` | A spinner row in each library's section | A `.secondary` label row in that library's section, after the sections that answered | — | Signed-out libraries are left out |
| Updates | `EmptyState` "No New Chapters" (+ Check Now when following) | `LoadingState` | `FailureState` | — | — |
| Settings, forms | — | Spinner in the confirming button's place | Red footnote under the section at fault | — | — |
| Reader | — | Spinner over the page until it opens | `FailureState` with the reader's title and message; Close stays | — | Alert: Sign In / Not Now |

**The first screen.** An empty Home with no shared library: `books.vertical` and "Add books and comics from Files or iCloud Drive, or add a library someone shares with you. You can also open the sample library to look around.", each way in a link in that sentence, the same pattern as every other empty screen.

## Lists and rows

- Navigation lists (Shared, Collections, Sites) are plain `List`s of `Label` rows with the system chevron, as Books' library list. Forms (Settings, Sites, Advanced) are inset grouped. Nothing in between: no hand-drawn rows with dividers.
- `PublicationRow` is the one row for anything readable: 44-pt cover, `.body` title, `.subheadline` secondary subtitle, status trailing.
- `PublicationCell` is the one cell for anything readable in a grid or shelf: cover, then `CoverCaption` (`.footnote` title, `.caption` secondary detail: author, series, or chapter, with the status after a middle dot when started or finished). Series cells (a collection's series, a site's series, a followed series) use `CoverCaption` too, with the count or new-chapter count as the detail.
- Grids and shelves never reserve blank lines under short titles; cells are top-aligned, so rows stay even.
- Menus with choices use `Section` headers ("Show", "Sort By", "View") so a picker reads as a setting, not a list of actions.
- While selecting in Library, a row's tap belongs to the list, not to the row.
