# App architecture

How the Chek app is put together, and the rules that keep its state
predictable. Read this before adding a screen, a store or a data model.

## Experience

Chek opens on **Home**, which puts whatever you were reading first, from any
source. **Library** is the books and comics kept on the device. **Browse**
holds the servers you've connected and everything on them. **Search** looks
through all of it at once. On iPhone these are tabs; on iPad the same tabs
become a sidebar that also lists each server's libraries.

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
   `PublicationRef`: `.local(UUID)` or `.server(ServerID, Int64)`. Routes,
   zoom transitions, reading positions and caches are all keyed by it.
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
| `SourceReadingState` | Your position in a chapter read straight from a server's source (an extension). Sources keep no positions on the server, so this copy is the only one. Added in `ChekSchemaV2`. |

Server catalogs (libraries, series, publications) and what sources list
(series, chapters, pages) are not stored. Sources run on the server, so the
app reaches them only through its API. Screen models load them page by page,
and covers go through `ImageLoader`'s memory and disk cache.

The store is named `Chek` so it never opens the default store Chibi Manga
left on devices that update.

## Stores

| Store | Owns |
| --- | --- |
| `AppRouter` | Tabs, navigation paths, the open reader and sheets. |
| `LibraryStore` | Importing, removing and marking local books. Views read books with `@Query`. |
| `ServerStore` | Connected accounts, their sign-in state and their clients. |
| `ProgressStore` | Saving positions for every source, and syncing them to servers. |
| `ReaderSettings` | Theme, text size and margins, kept in `UserDefaults`. |

All of them are `@MainActor`, created once in `ChekApp` and put in the
environment. Previews build them with in-memory storage.

## Reader

`ReaderScreen` gets a `ReadingItem`: what to open (`PublicationSource`), where
to start, and where to save. `ReaderSession` owns the `ReaderController`,
whether the controls are showing, and which panel is open. Only
`ProgressRecorder`, the scrubber and the page label read the location.

Server publications open without downloading first. EPUBs stream with range
requests, comics stream page by page, and other formats download to the
cache before they open.

## Server sync

Positions on a Chek server carry a revision. Saving sends the revision last
seen; if another device saved since, the server answers with its position
and Chek asks you which one to keep, as the server's contract requires. On
opening, a newer position from another device is offered as "Continue from
page 120 on iPad" rather than jumped to.
