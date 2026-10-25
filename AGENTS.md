# AGENTS.md

Guidance for anyone changing this repository, human or agent. Read it before writing code.

## What this is

The native Chek apps, starting with iPhone and iPad. Chek is a reader for books and comics wherever they are kept: local files first, then libraries served by Chek's own server, Komga and Kavita. Product direction lives in [readchek/chek's docs/product.md](https://github.com/readchek/chek/blob/main/docs/product.md).

## Decisions already made

- **Reading goes through Chek Reader.** Opening, laying out and paging publications belong to [readchek/chek-reader](https://github.com/readchek/chek-reader). When the app needs something the reader can't do, change the package rather than working around it here, since other apps use it too.
- **Local reading needs no account or server.** Server sources are added alongside the on-device library, not in place of it.
- **App identity.** Chek replaces Chibi Manga on the App Store, so it keeps Chibi Manga's bundle id `run.chibi.manga` and team `KZX5HZ32P9`, and its version and build stay above Chibi Manga's last builds (1.6, build 13); the next build after 2.0 (12) is 14. Chek's SwiftData store is named `Chek` so it never opens the default store Chibi Manga left on updated devices. The books Chibi Manga imported (`Documents/imports`, listed in `.library.json`) move into Chek's library on first launch, keeping each one's page.
- **Platforms.** Build with Xcode 27 and Swift 6.4, and deploy to iOS and iPadOS 26 or later. Put 27-only APIs behind `if #available`.
- **SwiftUI and SwiftData.** Books are `Book` models; each book's file and cover live in their own folder under Application Support, found by the book's id, because the app container's path changes between installs.
- **Mature content is turned on only on the web.** Under App Review Guideline 1.2, adult content from a web service must be off by default and turned on through a website. The iOS app offers Everyone and Teen and links to the web app in `web/` (app.chek.page), where adults turn on Mature after confirming their age. Don't add a way to turn it on in the app.
- **The admin panel** is the web app's `/admin` screens. The Chek server's image builds them from this repository's `main` with `bun run build:server` and serves them at `/admin`, so keep that build working and the screens working at both addresses.
- **The web app** in `web/` is SolidJS with TanStack Router, built with Vite and run with Bun, and deployed to Cloudflare as static files. It talks to each person's server from the browser with a bearer token, never cookies. It looks like the iOS app and chek.page: Tailwind CSS with the brand tokens in `web/src/styles.css` (blue, paper, mist and butter, Bricolage headlines, DM Sans text), and shadcn-style components after solid-ui, built on Kobalte, in `web/src/components/ui`. Fonts are served from the site, since its content security policy allows nothing else.
- **Positions** are Chek Reader `Locator` values, stored as their Readium-compatible JSON.
- **State.** Every value has one owner allowed to change it: a store, a screen model or a view's own `@State`. Phases are enums, not booleans, and stored data is versioned in `ChekSchema`. [docs/architecture.md](docs/architecture.md) has the layers and rules; read it before adding a screen, store or model.

## Build

```sh
xcodebuild build -project apple/Chek.xcodeproj -scheme Chek \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

CI runs this on every pull request, then the unit tests in `apple/ChekTests` on an iPhone simulator:

```sh
xcodebuild test -project apple/Chek.xcodeproj -scheme Chek \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

For `web/`, run `bun run typecheck`, `bun run lint`, `bun run format:check` and `bun run build` there; CI runs them too.

Before you push, build what you changed and run the tests. Tests cover logic that doesn't need a screen: address parsing, titles, statuses, settings, decoding. Add one when you fix a bug in such code. If your environment can't build the app, say so in the PR rather than guessing.

## Code conventions

- **Swift 6 language mode** with strict concurrency. Code is main-actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); mark file and parsing work `nonisolated` or `@concurrent` so it stays off the main thread.
- **SwiftUI.**
  - Use `@Observable`, and keep fast-changing values such as the reader's `location` out of views that don't need them.
  - Use `.leading` and `.trailing`, never left and right.
  - Don't use soft-deprecated APIs such as `NavigationView` or the old `onChange`.
- **Localization.** User-facing strings go through `Localizable.xcstrings`.
- **Style.** Four-space indentation, one type per file where practical, and comments that explain why rather than what.

## Pull requests

- For now, while the app's shape is still being worked out, commit straight to `main` at meaningful checkpoints instead of opening PRs. The same goes for Chek Reader changes the app needs.
- Once PRs are back: branch from `main`, keep each PR to one change, and merge by squash.
- Fill in the PR template with "Before", "After" and "How" in plain language.
- Update the README when requirements or usage change, and this file when a convention or decision changes.
