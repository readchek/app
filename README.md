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

> In development. The iOS app keeps a library of books on the device: add EPUB, PDF, CBZ and CBT comics, MOBI, AZW3, FictionBook, plain text and Markdown files from Files, and each one opens where you left it. Reading from Chek's server, Komga and Kavita comes next.

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

Chek Reader comes from its `main` branch through Swift Package Manager, so
**File → Packages → Update to Latest Package Versions** picks up its newest
changes.

## Repository layout

```text
apple/
  Chek.xcodeproj/   The app project
  Chek/             App sources
    Library/        The on-device library: import, storage, covers and the grid
    Reader/         The reading screen around Chek Reader
.github/workflows/  CI
```

See [AGENTS.md](AGENTS.md) for the conventions contributors and coding agents follow.
