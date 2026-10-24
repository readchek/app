# Language and UI patterns

How Chek speaks and how its screens are put together. The aim is an app that reads like one of Apple's own: calm, specific, the same from screen to screen. Rules cite the Human Interface Guidelines page behind them (`hig:/writing` means `developer.apple.com/design/human-interface-guidelines/writing`).

## Voice

- Speak to one reader, plainly. Say what happened and what to do next; nothing else. (`hig:/writing`, "Be clear")
- Calm, not chatty. No rhetorical questions ("Someone shared a library with you?"), no interjections, no hedging ("It may be busy"), no exclamation marks anywhere.
- Say "you"; never "we" or "I". Use "your" only to tell yours from someone else's ("your library, shared libraries, and sites"); otherwise drop it ("Library", not "Your Library"). (`hig:/writing`, "Use possessive pronouns sparingly")
- Contractions are fine ("Can't Open This Book", "doesn't"). "Please" and "sorry" are not.
- Buttons start with a verb and name the thing: "Add Books", "Remove Download", "Sign In". Never "OK" except to dismiss a purely informational alert; never "Yes"/"No". (`hig:/buttons`, `hig:/alerts`)
- No jargon in reader-facing screens: not "server", "source", "extension", "publication", "session", "sync", "cache", "admin". Technical words live only on the Advanced screen.
- American spelling, serial comma: "Books, Comics, and Authors".

## Capitalization and punctuation

| Element | Style | Example |
|---|---|---|
| Navigation titles, tab titles, section headers, buttons, menu items, toggles, picker options, status values in rows | Title Case, no end punctuation | "Add Shared Library", "Signed Out", "Oldest First" |
| Titles of alerts, confirmation dialogs, and empty states | Title Case fragment; a question mark only when asking | "No Books", "Couldn't Connect", "Remove “Home”?" |
| Messages, descriptions, footers, placeholders that are sentences, captions that are sentences | Sentence case, full sentences, end with a period | "Books and comics you add appear here." |
| Text-field labels and short placeholders | Title Case, no period | "User Name", "Address" |
| Menu items that open a confirmation or a form before acting | Trailing ellipsis | "Delete…", "Remove…" |
| Buttons in forms and dialogs, swipe actions | No ellipsis | "Remove All Downloads" |

Title Case capitalizes every word except articles, coordinating conjunctions, and prepositions under four letters; the first and last word are always capitalized ("Mark as Finished", "Sign In to Home"). Drop articles from menu items ("Close Sample Library", not "Close the Sample Library"). (`hig:/menus`, "Labels"; `hig:/alerts`, "Content")

## Terminology

One word per idea, everywhere, including accessibility labels.

| Use | For | Not |
|---|---|---|
| Library | the books and comics on this device | Your Library, local library |
| shared library (Shared tab) | a Chek server someone gave you access to | server, Chek library, account, connection |
| the library's administrator | whoever runs a shared library | whoever runs/shares this library, admin, owner, them |
| collection | a library inside a shared library | server library |
| site | an installed extension that reads a manga or comic site | source, extension |
| repository | where sites are downloaded from (Advanced only) | — |
| Sample Library | the public demo | demo, sample books, try |
| book / comic / series / chapter | what's read | publication, item, title (as a noun for a book) |
| reading position | where you are in a book or chapter | place, progress, location |
| Add / Remove | put something in a list, take it out (nothing is destroyed) | install, uninstall, connect, close (except the Sample Library) |
| Delete | destroy a file on this device | remove (for books) |
| Download / Remove Download | keep a comic or chapter on the device | save, kept, offline copy |
| Sign In / Sign Out / Signed Out | a shared library's session | log in, session ended |
| Mark as Finished / Mark as Unread | books and chapters alike | Mark as Read |
| Follow / Following / Unfollow | a series watched for new chapters | subscribe |
| New | unread and unopened | unseen |
| Continue Reading / Recently Added / Downloaded / Following / Collections / Sites | shelf and section names | Continue, New in |

## Standard wording

- **Empty screen.** Title "No <Things>" (no "Yet"); one sentence on what appears here and how to get it; at most one button, a verb phrase. "No Books — Add books and comics from Files or iCloud Drive. They're stored on this device. [Add Books]". (`hig:/writing`, "Provide clear next steps on any blank screens")
- **Load failed.** Title names what failed, message says the fix: "Couldn't Connect — Check your internet connection and try again. [Try Again]". A refresh that fails with content still showing is a one-line notice above it, not an alert. (`hig:/alerts`, "Avoid showing an alert when your app starts")
- **Signed out.** Title "Signed Out"; message "Sign in to <Library> to keep reading."; button "Sign In".
- **Confirming removal.** Title "Remove “<Name>”?" or "Delete “<Name>”?" (with a count: "Delete 3 Books?"); message says only what is lost and what is kept; the action button repeats the verb with its object ("Delete Book", "Remove Library"). Cancel is implicit.
- **Loading.** A spinner, no caption, unless it will take more than a moment, then a determinate ring and a noun ("Downloading"). (`hig:/progress-indicators`, `hig:/loading`)
- **Footers explaining a setting.** One or two sentences, present tense, describing what happens when it's on; don't describe the off state. (`hig:/writing`, "Keep settings labels clear and simple")
- **Errors next to a field.** Red footnote under the section, no icon, telling the reader what to enter: "Check the address. Enter the one you were given, such as books.example.com." (`hig:/writing`, "Show hints in text fields")
- **Notifications.** Title is the series; body "A new chapter is available." / "3 new chapters are available."

## UI patterns

Patterns follow what the app already does where that was sound, so changes stay small.

- **Push vs sheet.** Push for going deeper into content (a library, a series, Sites, Advanced). Sheet for a task you finish and leave: Add Shared Library, Sign In, Add Repository, Settings, the reader's panels. One sheet at a time; never a sheet from a sheet. (`hig:/sheets`, `hig:/modality`)
- **Sheet toolbars.** Cancel or Close is the system `xmark` symbol on the leading edge. The confirming action is a text button on the trailing edge, `.prominent`, named for what it does: "Add", "Save", "Sign In"; "Done" only when the sheet's changes apply as you make them (Settings). Never a checkmark glyph for Done or Add. Panels that only navigate (Contents, Chapters, Appearance) have Close and nothing else. (`hig:/toolbars`, "Navigation" and "Actions"; `hig:/sheets`, "iOS, iPadOS")
- **Screen toolbars.** Add is `plus` on the trailing edge. Everything else on a screen goes in one More menu (`ellipsis`, no circle) on the trailing edge; Edit is a text button on the leading edge. At most two items a side. (`hig:/toolbars`)
- **Confirmation dialog vs alert.** A `confirmationDialog` with a visible title confirms something the reader chose: deleting, removing, downloading many. An `alert` is for what they didn't choose: a load that failed, a sign-in that's needed, a position saved on another device. Informational alerts take one "OK"; alerts with a choice name both buttons ("Sign In" / "Not Now"). (`hig:/action-sheets`, `hig:/alerts`)
- **Destructive actions.** Red (`role: .destructive`) in menus and dialogs, last in the menu after a divider, always confirmed unless undoable. Swipe actions are red-tinted but not `.destructive`, so the row waits for the confirmation. Resetting settings is not destructive. (`hig:/context-menus`, `hig:/buttons`, "Role")
- **Context menus and swipe actions.** Every item has a symbol; the same action uses the same symbol everywhere (`trash`, `checkmark.circle`, `circle`, `arrow.down.circle`, `square.and.arrow.up`, `pencil`, `key`). Most-used first, destructive last. Anything in a context menu is reachable another way too. (`hig:/context-menus`, `hig:/menus`, "Icons")
- **Menus.** Verb phrases, no articles, grouped by dividers; a toggled state is a checkmark in a picker, not two items.
- **Lists vs grids.** Covers in a grid (Library, collections, sites, search results from sites); text rows in a plain list (chapters, a series' books, search results from libraries, Settings forms). Section headers in scrolling pages are `SectionHeader`, bold title with a chevron only when they lead somewhere. (`hig:/lists-and-tables`)
- **Empty and failed screens.** Always `EmptyState` / `FailureState` (`ContentUnavailableView` underneath): system symbol, title, one sentence, one prominent button at default size, optional quiet links at the foot. No custom layouts, no oversized type, no full-width buttons. The one exception is the first screen (an empty Reading Now): it keeps the standard symbol, title and sentence, but its Add Books button spans the foot, as on a welcome screen, with the other ways in as quiet links under it.
- **Search.** One Search tab for everything; a local search field, always visible, only inside a collection or a site, with the prompt "Search <Name>". No results is the system `ContentUnavailableView.search`. (`hig:/searching`, `hig:/search-fields`)
- **Tabs.** Reading Now, Library, Shared, Search. Tabs are nouns; badges only for things that need attention. (`hig:/tab-bars`)
- **Onboarding.** None. The first screens are empty states that lead to content; the reader's one-time hint is the only overlay, and it's dismissed with a tap. (`hig:/onboarding`)
