# AGENTS.md

Guidance for anyone changing this repository, human or agent. Read it before writing code.

## What this is

The native Chek apps, starting with iPhone and iPad. Chek is a reader for books and comics wherever they are kept: local files first, then libraries served by Chek's own server, Komga and Kavita. Product direction lives in [readchek/chek's docs/product.md](https://github.com/readchek/chek/blob/main/docs/product.md).

## Decisions already made

- **Reading goes through Chek Reader.** Opening, laying out and paging publications belong to [readchek/chek-reader](https://github.com/readchek/chek-reader). When the app needs something the reader can't do, change the package rather than working around it here, since other apps use it too.
- **Local reading needs no account or server.** Server sources are added alongside the on-device library, not in place of it.
- **Platforms.** Build with Xcode 27 and Swift 6.4, and deploy to iOS and iPadOS 26 or later. Put 27-only APIs behind `if #available`.
- **SwiftUI and SwiftData.** Books are `Book` models; each book's file and cover live in their own folder under Application Support, found by the book's id, because the app container's path changes between installs.
- **Positions** are Chek Reader `Locator` values, stored as their Readium-compatible JSON.

## Build

```sh
xcodebuild build -project apple/Chek.xcodeproj -scheme Chek \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

CI runs this on every pull request. Before you push, build what you changed. If your environment can't build the app, say so in the PR rather than guessing.

## Code conventions

- **Swift 6 language mode** with strict concurrency. Code is main-actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); mark file and parsing work `nonisolated` or `@concurrent` so it stays off the main thread.
- **SwiftUI.**
  - Use `@Observable`, and keep fast-changing values such as the reader's `location` out of views that don't need them.
  - Use `.leading` and `.trailing`, never left and right.
  - Don't use soft-deprecated APIs such as `NavigationView` or the old `onChange`.
- **Localization.** User-facing strings go through `Localizable.xcstrings`.
- **Style.** Four-space indentation, one type per file where practical, and comments that explain why rather than what.

## Pull requests

- Branch from `main`, keep each PR to one change, and merge by squash.
- Fill in the PR template with "Before", "After" and "How" in plain language.
- Update the README when requirements or usage change, and this file when a convention or decision changes.
