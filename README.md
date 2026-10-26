<p align="center">
  <img src=".github/assets/mark.svg" alt="Chek" width="80" height="80" />
</p>

<h1 align="center">Chek</h1>

<p align="center"><strong>Just one more chapter.</strong><br />A reader for your books and comics, on iPhone and iPad.</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/chek-books-comics/id6761271144"><strong>Get it on the App Store</strong></a>
  ·
  <a href="https://chek.page">Website</a>
  ·
  <a href="AGENTS.md">Contributor guide</a>
  ·
  <a href="https://github.com/readchek/chek/issues/new/choose">Report a problem</a>
</p>

<p align="center">
  <a href="https://assets.chek.page/chek-promo-16x9.mp4"><img src="https://raw.githubusercontent.com/readchek/chek.page/main/public/assets/video/promo-16x9-poster.webp" alt="Watch the Chek film" width="560" /></a>
</p>

This repository holds the native Chek apps, starting with iPhone and iPad,
and Chek on the web. Chek 2.0 is live on the App Store.

## What the app does

- **Your own files.** Add EPUB, PDF, CBZ and CBT comics, MOBI, AZW3,
  FictionBook, plain text and Markdown from Files. Each one opens where you
  left it, offline and without an account.
- **Your own server.** Connect a [Chek server](https://github.com/readchek/chek)
  to read its libraries and the sources its extensions add. Follow a series
  to hear about new chapters, and download chapters to read offline.
- **A demo to try.** Try the Demo, from Settings or an empty screen,
  connects to demo.chek.page until the app is closed.

Books are read with [Chek Reader](https://github.com/readchek/chek-reader),
the reading engine Chek maintains as a standalone Swift package. The server
is a separate project, and the app never needs it.

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

### Chek Reader

Chek Reader comes through Swift Package Manager, pinned to a release
(`0.1.0` up to the next minor), so a build is the same today and next month.

- **Take a new release.** Raise the version in the project's package
  dependency, then let **File → Packages → Update to Latest Package Versions**
  rewrite `Package.resolved`.
- **Try unreleased changes.** Add the package locally with
  **File → Add Package Dependencies → Add Local**. It overrides the pinned one
  until you remove it.

## The web app

`web/` is Chek on the web, served at [app.chek.page](https://app.chek.page).
It has three parts so far:

- **The reading app**, on par with the iOS app. You sign in to one or more
  Chek servers, and stay signed in until you sign out. It reads comics,
  EPUB, PDF, plain text and Markdown with Chek Reader, browses shared libraries
  and sites, and installs as an app that opens offline. The code is in
  `src/app`.
- **Content settings**, where adults turn on mature series. The iOS app
  doesn't offer that, so it opens this page in Safari, signed in with a
  one-time code from the server.
- **The admin panel** at `/admin`, where a server's admins set it up with
  its setup token, then manage libraries and their scans, people and the
  libraries each one reads, extension repositories and settings.

The server image bundles the whole app, built with `bun run build:server`,
at `http://<server>:8080/`, with the admin panel at `/admin`, since an https
page can't reach a server on plain http. app.chek.page reaches servers with
https addresses.

- **Stack.** SolidJS with TanStack Router, built with Vite and run with
  [Bun](https://bun.sh).
- **Look.** It follows the app and chek.page: Tailwind CSS with the brand's
  colors and fonts in `src/styles.css`, and shadcn-style components from
  [solid-ui](https://www.solid-ui.com), built on Kobalte, in `src/components/ui`.

```sh
cd web
bun install
bun run dev        # http://localhost:18358
bun run typecheck && bun run lint && bun run format:check && bun run build
bun run build:server   # the app the server serves, in dist-server/
```

- **Deploy.** Every push to `main` that changes `web/` publishes it to
  Cloudflare at app.chek.page through the Deploy web app workflow, which
  signs in with the `CLOUDFLARE_API_TOKEN` repository secret. To redeploy
  without a push, run the workflow from the Actions tab. From your own
  machine, `bun run deploy` builds and publishes it after `cf auth login`.
- **Local server.** A server accepts calls from the origins in
  `CHEK_WEB_ORIGINS` (`https://app.chek.page` by default). To use a local
  server with the dev page, start it with
  `CHEK_WEB_ORIGINS=http://localhost:18358`. Once the page is served over
  https, it reaches only https servers.

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
web/                Chek on the web, at app.chek.page
docs/               Architecture notes
.github/workflows/  CI
```

See [AGENTS.md](AGENTS.md) for the conventions contributors and coding agents follow.

## License

The Chek apps are licensed under the [GNU Affero General Public License v3.0](LICENSE).
The fonts in `web/src/fonts` keep their own SIL Open Font License, next to each font.
