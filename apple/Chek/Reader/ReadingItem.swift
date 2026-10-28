import ChekReader
import Foundation

/// Everything the reader needs to open a publication: what it is, where its
/// bytes come from and where to start.
struct ReadingItem: Identifiable {
    /// Where the reader gets the publication.
    enum Content {
        /// Ready to open as it is.
        case source(PublicationSource)
        /// Has to be fetched first, for formats that can't stream. The
        /// reader shows progress while ``Download`` runs.
        case download(Download)
    }

    let ref: PublicationRef
    let title: String
    let subtitle: String?
    let kind: PublicationKind
    let content: Content
    var startLocation: Locator?
    /// The chapter this is, when it's read straight from a source, so the
    /// reader can offer the one after it.
    var sourceChapter: SourceChapterRef?
    /// The publication this is, when it's read from a server, so the
    /// reader can offer the ones either side of it in its series.
    var serverPublication: RemotePublication?
    /// The series this is one of, by title, when it's part of one, so
    /// the reader can offer the chapters or volumes either side of it.
    var series: String?
    /// What settings made for this publication also apply to: its series,
    /// when it's one of a series, since a manga reads the same way
    /// throughout. Nil when the publication is only itself.
    var seriesKey: String?
    /// Whether every page is on the device, so reading it needs nothing
    /// from its server, such as a session.
    var isOnDevice = false
    /// The license an openly licensed book came with, to show with it.
    var rights: ChekAPI.Rights?

    var id: PublicationRef { ref }

    /// Where settings made while reading this are kept: its series when
    /// it has one, otherwise the publication itself.
    var settingsKey: String { seriesKey ?? ref.storageKey }

    init(ref: PublicationRef, title: String, subtitle: String? = nil, kind: PublicationKind, content: Content, startLocation: Locator?) {
        self.ref = ref
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.content = content
        self.startLocation = startLocation
    }

    init(_ book: Book) {
        self.init(
            ref: book.ref,
            title: book.title,
            subtitle: book.authors.isEmpty ? nil : book.authors,
            kind: book.kind,
            content: .source(.file(book.fileURL)),
            startLocation: book.savedLocation
        )
        series = book.seriesTitle.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A file the reader fetches before opening it.
struct Download: Sendable {
    let request: URLRequest
    /// Where the finished file is kept, so opening it again is instant.
    let destination: URL
}
