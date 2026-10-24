import Foundation
import Observation

/// The app's top-level sections.
enum AppTab: Hashable {
    case home, library, browse, search
    /// A server of its own in the iPad sidebar, where there's room to put
    /// each one a tap away.
    case server(UUID)
}

/// A screen pushed onto a tab's navigation stack.
enum Route: Hashable {
    case server(UUID)
    case serverLibrary(UUID, ChekAPI.Library)
    case series(UUID, seriesID: Int64, title: String)
    /// A source's series, searchable: the server and the installed extension.
    case source(UUID, ChekAPI.InstalledExtension)
    case sourceSeries(UUID, source: String, seriesID: String, title: String)
    /// The extensions a server offers, to install and update.
    case extensions(UUID)
    /// New chapters across every followed series.
    case updates
}

/// Something shown in a sheet over the whole app.
enum AppSheet: Identifiable, Hashable {
    case settings
    case addServer
    /// Signing back in to an account whose session ended.
    case signIn(UUID)

    var id: Self { self }
}

/// Owns where you are in the app: the selected tab, each tab's stack, any
/// sheet and the open reader. Everything that moves you around, from a tap
/// to a file opened from another app, goes through here.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var homePath: [Route] = []
    var browsePath: [Route] = []
    var searchPath: [Route] = []
    /// Each server tab's own stack, by server.
    var serverPaths: [UUID: [Route]] = [:]
    var sheet: AppSheet?
    /// The publication open in the reader.
    var reading: ReadingItem?
    /// Whether the file picker for adding books is showing.
    var isImportingFiles = false
    /// A server publication being prepared to open, for showing progress
    /// on the cover you tapped.
    private(set) var opening: PublicationRef?
    /// Why the last server publication couldn't open.
    var openingFailure: OpeningFailure?
    /// What was being opened when a sign-in was needed, opened again once
    /// you've signed in rather than making you find it a second time.
    private(set) var pendingAfterSignIn: PendingOpen?

    func open(_ item: ReadingItem) {
        sheet = nil
        reading = item
    }

    /// A server is gone, so nothing points at it any more: its tab, if
    /// selected, gives way to Browse, and its stack goes.
    func serverRemoved(_ account: UUID) {
        serverPaths[account] = nil
        if tab == .server(account) {
            tab = .browse
        }
        browsePath.removeAll { if case .server(account) = $0 { true } else { false } }
    }

    /// Pushes `route` onto the selected tab's stack, as a tapped shelf
    /// header does. Library has no stack and no shelves, so nothing
    /// pushes from it.
    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .browse: browsePath.append(route)
        case .search: searchPath.append(route)
        case .library: break
        case .server(let account): serverPaths[account, default: []].append(route)
        }
    }

    /// Goes to `route` on Reading Now, over whatever is open, as a tapped
    /// notification does.
    func show(_ route: Route) {
        sheet = nil
        reading = nil
        tab = .home
        homePath = [route]
    }

    /// Opens a server publication once ``ServerSync`` has it ready. A second
    /// tap while one is opening is ignored.
    func open(_ publication: RemotePublication, using sync: ServerSync) {
        guard opening == nil else { return }
        opening = publication.ref
        Task {
            defer { opening = nil }
            do {
                open(try await sync.readingItem(for: publication))
            } catch {
                let needsSignIn = sync.isSignedOut(of: publication.server)
                openingFailure = OpeningFailure(error: DisplayError(error), signIn: needsSignIn ? publication.server : nil)
                if needsSignIn { pendingAfterSignIn = .publication(publication) }
            }
        }
    }

    /// Opens a chapter from one of a server's sources once its pages are
    /// listed. A second tap while one is opening is ignored.
    /// Opens a chapter from one of a server's sources. The reader fetches
    /// its pages itself, so it opens at once.
    func open(_ chapter: SourceChapterRef, using sync: ServerSync) {
        do {
            open(try sync.readingItem(for: chapter))
        } catch {
            let needsSignIn = sync.isSignedOut(of: chapter.server)
            openingFailure = OpeningFailure(error: error, signIn: needsSignIn ? chapter.server : nil)
            if needsSignIn { pendingAfterSignIn = .chapter(chapter) }
        }
    }

    /// Opens what a sign-in was needed for, now that it's done.
    func resumePendingOpen(using sync: ServerSync) {
        guard let pending = pendingAfterSignIn else { return }
        pendingAfterSignIn = nil
        switch pending {
        case .publication(let publication): open(publication, using: sync)
        case .chapter(let chapter): open(chapter, using: sync)
        }
    }

    func dropPendingOpen() {
        pendingAfterSignIn = nil
    }

    func closeReader() {
        reading = nil
    }

    /// Shows the file picker, from wherever you asked to add books.
    func addBooks() {
        isImportingFiles = true
    }
}

/// Why a server publication couldn't open, and the server to sign in to
/// when signing in again is what would fix it.
struct OpeningFailure: Hashable {
    var error: DisplayError
    var signIn: UUID?
}

/// Something that was being opened when a sign-in got in the way.
enum PendingOpen {
    case publication(RemotePublication)
    case chapter(SourceChapterRef)
}
