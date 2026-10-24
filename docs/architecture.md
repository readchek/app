# App architecture

How the Chek app is put together, and the rules that keep its state
predictable. Read this before adding a screen, a store or a data model.

## Experience

Chek opens on **Reading Now**, which puts whatever you were reading first,
from anywhere, then a shelf for each shared library and each site you've
added. **Library** is the books and comics kept on the device. **Shared**
holds the libraries people share with you (each one a Chek server) and
everything in them. **Search** looks through all of it at once. On iPhone
these are tabs; on iPad the same tabs become a sidebar that also lists each
shared library.

The app is for readers, not the people who run servers. It says "shared
library" rather than server, "site" rather than source or extension, and
keeps repositories, tokens and admin settings on one Advanced screen or on
the server's own web page.

Reading is full screen. Opening a book zooms it out of its cover, and the
controls stay out of the way until you tap the middle of the page. They are
Liquid Glass bars: the title, contents and reading settings at the top, and a
scrubber with your place in the book at the bottom.

## Layers

```text
Views            SwiftUI. Read state, send intents. Never own business logic.
Screen models    @Observable, one per screen that loads data. Owned by @State.
Stores           @Observable, one per domain, alive for the whole app.
Services         Plain Sendable types: the server client, Keychain, importer,
                 image loader. No UI, no observation.
Persistence      SwiftData for what must survive a relaunch. Keychain for tokens.
```

Data flows down and intents flow up. A view never writes to a model object
directly; it calls a store or screen model method that names the intent, such
as `library.markFinished(book)` or `reader.toggleControls()`. That keeps
every write to a piece of state in one place you can search for.

## Rules

1. **One owner for every piece of state.** Each value has exactly one place
   it's stored and one type that's allowed to change it. Everything else
   reads it or asks the owner to change it. If two places need to agree, one
   of them is derived from the other, never synced by hand.
2. **Phases are enums, not booleans.** Loading is `LoadState`
   (`idle`, `loading`, `loaded`, `failed`), a server connection is
   `ConnectionState`, a reading session is `ReaderController.State`. There is
   no `isLoading` next to an `error` next to `items` that can disagree.
3. **Identity is stable and typed.** Anything you can open is a
   `PublicationRef`: `.local(UUID)`, `.server(ServerID, Int64)` or
   `.source(ServerID, extension, chapter)`. Routes, zoom transitions,
   reading positions and caches are all keyed by it.
4. **Async work belongs to a lifetime.** Screen loads run in `.task(id:)`, so
   leaving the screen cancels them. Stores tag long work with a generation
   and drop results from work that was replaced. Pagination keeps at most one
   page request in flight.
5. **Persist first, sync after.** A reading position is written to the device
   on every page turn and then pushed to its server. The device copy is what
   the app shows; the server copy is what other devices see.
6. **Observe narrowly.** Fast-changing values, such as the reader's
   location, are read only by the small views that show them. Rows take the
   fields they draw, not whole models. Derived values that many views read
   are cached as stored properties.
7. **Navigation is state.** `AppRouter` owns the selected tab, each tab's
   path of typed `Route` values, and what's presented. Deep links, imports and
   "open this book" all go through it.

## Persistence

SwiftData models, versioned from the start with `ChekSchema` so later changes
migrate instead of resetting:

| Model | Holds |
| --- | --- |
| `Book` | A publication imported to the device: metadata, file name, position. |
| `ServerAccount` | A connected server: kind, address, user. The token is in the Keychain under the account's id. |
| `RemoteReadingState` | Your position in a server publication, with enough to show it in Continue Reading offline, its last synced revision and whether it still needs uploading. |
| `FollowedSeries` | A series you follow from a source: its title and cover, how many chapters it had when last checked, and which chapters you haven't seen. Added in `ChekSchemaV4`. |
| `SourceReadingState` | Your position in a chapter read straight from a server's source (an extension). Sources keep no positions on the server, so this copy is the only one. Added in `ChekSchemaV2`. |

Server catalogs (libraries, series, publications) and what sources list
(series, chapters, pages) are loaded page by page by screen models, not
stored in SwiftData. Sources run on the server, so the app reaches them only
through its API. What was shown last is kept as files, so screens open at
once and still work when a server can't be reached:

| Where | What | Cleared by |
| --- | --- | --- |
| Caches/Covers | Cover images, by `PublicationRef` key (`ImagePipeline`). | Settings, or iOS when space is short. |
| Caches/Servers | Books downloaded from servers to open, and each server's last Reading Now and server screen (`HomeSnapshot`, `ServerHomeSnapshot`). | Settings, removing the server, or iOS. |
| Application Support/Chapters | Source chapters downloaded to read offline, a folder of pages per chapter with a note of its series (`ChapterFiles`, `PageFolder`). | You, from the series or Settings; removing the server. |
| Application Support/Publications | Server comics downloaded to read offline, a folder of pages per publication with the publication as its note (`PublicationFiles`). | You, from the series or Settings; removing the server. |
| Application Support/SourceSeries | Each source series' last listing (`SeriesCache`), so the series screen, the chapter list and Next Chapter work offline. | Removing the server. |

The store is named `Chek` so it never opens the default store Chibi Manga
left on devices that update.

## Stores

| Store | Owns |
| --- | --- |
| `AppRouter` | Tabs, navigation paths, the open reader and sheets. |
| `LibraryStore` | Importing, removing and marking local books. Views read books with `@Query`. |
| `ServerStore` | Connected accounts, their sign-in state and their clients. Also the demo: a temporary account on demo.chek.page with a fixed id (`DemoMode`), dropped at the next launch, whose reading places never sync since the account is shared. |
| `ProgressStore` | Saving positions for every source, and syncing them to servers. |
| `ReaderSettings` | Theme, text size and margins, kept in `UserDefaults`, and the reading direction chosen per series. |
| `FollowStore` | Following series from sources and checking them for new chapters, in the app and from the background refresh task (`FollowRefresh`), which notifies. New chapters across every followed series are listed on the Updates screen, from each series' kept listing. |
| `Downloads` | Which source chapters and server comics are on the device, and the queue that fetches them one at a time. |

All of them are `@MainActor`, created once in `ChekApp` and put in the
environment. Previews build them with in-memory storage.

## Reader

`ReaderScreen` gets a `ReadingItem`: what to open (`PublicationSource`), where
to start, and where to save. `ReaderSession` owns the `ReaderController`,
whether the controls are showing, and which panel is open. Only
`ProgressRecorder`, the scrubber and the page label read the location.

On a screen wider than it is tall, such as an iPad held sideways, comics
show two pages at a time after the cover, which is Chek Reader's doing.

Server publications open without downloading first. EPUBs stream with range
requests, comics stream page by page, and other formats download to the
cache before they open; a download that's stopped keeps what arrived and
continues next time. Page sources reach their server through
`ServerAccess`, which looks up the signed-in client on every request and
tells `ServerStore` when the server ends the session, so the reader can
offer to sign in again and pick up at the same page. A downloaded source
chapter reads from its folder instead.

## Server sync

Positions on a Chek server carry a revision. Saving sends the revision last
seen; if another device saved since, the server answers with its position
and Chek asks you which one to keep, as the server's contract requires. On
opening, a newer position from another device is offered as "Continue from
page 120 on iPad" rather than jumped to.
