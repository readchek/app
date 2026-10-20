import SwiftUI

/// Anything shown as a cover or a row, from the device or a server, with
/// the few values every cell draws. Cells take this instead of the model,
/// so books and server publications look and behave the same.
struct PublicationItem: Identifiable {
    enum Source {
        case local(Book)
        case remote(RemotePublication)
        /// A chapter read straight from a server's source.
        case chapter(SourceChapterRef)
    }

    let source: Source
    let title: String
    /// Author for books, series or format for others.
    let subtitle: String?
    let cover: CoverSource
    let status: ReadingStatus

    var id: PublicationRef {
        switch source {
        case .local(let book): book.ref
        case .remote(let publication): publication.ref
        case .chapter(let chapter): chapter.ref
        }
    }

    init(_ book: Book) {
        source = .local(book)
        title = book.title
        subtitle = book.authors.isEmpty ? nil : book.authors
        cover = book.coverURL.map(CoverSource.file) ?? .none
        status = book.readingStatus
    }

    init(_ publication: RemotePublication, status: ReadingStatus, cover: CoverSource, showsSeries: Bool = true) {
        source = .remote(publication)
        title = publication.displayTitle
        // A series named like its one book says nothing twice.
        let series = publication.seriesTitle
        subtitle = showsSeries && series?.localizedCaseInsensitiveCompare(title) != .orderedSame ? series : nil
        self.cover = cover
        self.status = status
    }

    /// A source chapter you've opened, titled by its series since that's
    /// what you'd look for, with the chapter under it.
    init(_ state: SourceReadingState, cover: CoverSource) {
        source = .chapter(SourceChapterRef(state))
        title = state.seriesTitle
        subtitle = state.chapterTitle
        self.cover = cover
        status = state.readingStatus
    }
}

/// Opens an item in the reader: books at once, server publications once
/// their position is checked.
struct OpenPublicationButton<Label: View>: View {
    let item: PublicationItem
    @ViewBuilder let label: Label
    @Environment(AppRouter.self) private var router
    @Environment(ServerSync.self) private var sync

    var body: some View {
        Button {
            switch item.source {
            case .local(let book): router.open(ReadingItem(book))
            case .remote(let publication): router.open(publication, using: sync)
            case .chapter(let chapter): router.open(chapter, using: sync)
            }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
    }

    private var isUnavailable: Bool {
        if case .remote(let publication) = item.source { !publication.isAvailable } else { false }
    }
}
