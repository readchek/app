<p align="center">
  <img src=".github/assets/mark.svg" alt="Chek" width="80" height="80" />
</p>

<h1 align="center">Chek</h1>

<p align="center">Your books and comics. Your choice of source.</p>

<p align="center">
  <a href="https://chek.page">Chek</a>
  ·
  <a href="AGENTS.md">Contributor guide</a>
  ·
  <a href="https://github.com/readchek/app/issues">Issues</a>
</p>

> In development. The iOS app keeps a library of books on the device: add EPUB, PDF, CBZ and CBT comics, MOBI, AZW3, FictionBook, plain text and Markdown files from Files, and each one opens where you left it. Connect a Chek server to read its libraries and the sources its extensions add, follow series to hear about new chapters, and download chapters to read offline. Try the Demo, from Settings or an empty screen, connects to demo.chek.page until the app is closed. Komga and Kavita come next.

## Overview

This repository holds the native Chek apps, starting with iPhone and iPad.
Books are read with [Chek Reader](https://github.com/readchek/chek-reader), the
reading engine Chek maintains as a standalone Swift package. The
[Chek server](https://github.com/readchek/chek) is a separate project, and the
app never needs it: local files work offline without an account.

## Requirements

- Xcode 27 and Swift 6.4 to build.
- Runs on iOS and iPadOS 26 or later.

## Development

You can work without a phone, in the iOS Simulator:

```sh
open apple/Chek.xcodeproj
```

Or from the command line:

```sh
xcodebuild build -project apple/Chek.xcodeproj -scheme Chek \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

The unit tests run on an iPhone simulator:

```sh
xcodebuild test -project apple/Chek.xcodeproj -scheme Chek \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

Chek Reader comes through Swift Package Manager, pinned to a release
(`0.1.0` up to the next minor), so a build is the same today and next month.
To take a new reader release, raise the version in the project's package
dependency and let **File → Packages → Update to Latest Package Versions**
rewrite `Package.resolved`. To work against unreleased reader changes, add
the package locally with **File → Add Package Dependencies → Add Local**,
which overrides the pinned one until you remove it.

## Repository layout

```text
apple/
  Chek.xcodeproj/   The app project
  Chek/             App sources
    App/            Entry point, routing and the root tabs
    Home/           Reading Now: what you're reading, following and what's new
    Library/        The on-device library: import, storage, covers and the grid
    Reader/         The reading screen around Chek Reader
    Servers/        Chek servers: connecting, browsing, syncing positions
    Sources/        A server's sources: browsing, following, downloads
    Search/         Searching everything at once
    Settings/       Settings and storage
    Model/          SwiftData models and their schema versions
    Components/     Views and image loading shared across screens
  ChekTests/        Unit tests
docs/               Architecture notes
.github/workflows/  CI
```

See [AGENTS.md](AGENTS.md) for the conventions contributors and coding agents follow.
