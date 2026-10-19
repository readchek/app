import Foundation
import Observation

/// The app's top-level sections.
enum AppTab: String, Hashable {
    case home, library, browse, search
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

    func open(_ item: ReadingItem) {
        sheet = nil
        reading = item
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
                openingFailure = OpeningFailure(
                    error: DisplayError(error),
                    signIn: sync.isSignedOut(of: publication.server) ? publication.server : nil
                )
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
            openingFailure = OpeningFailure(
                error: error,
                signIn: sync.isSignedOut(of: chapter.server) ? chapter.server : nil
            )
        }
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
