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
    let startLocation: Locator?
    /// The chapter this is, when it's read straight from a source, so the
    /// reader can offer the one after it.
    var sourceChapter: SourceChapterRef?
    /// What settings made for this publication also apply to: its series,
    /// when it's one of a series, since a manga reads the same way
    /// throughout. Nil when the publication is only itself.
    var seriesKey: String?

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
    }
}

/// A file the reader fetches before opening it.
struct Download: Sendable {
    let request: URLRequest
    /// Where the finished file is kept, so opening it again is instant.
    let destination: URL
}
