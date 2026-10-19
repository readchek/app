import SwiftUI

/// Anything shown as a cover or a row, from the device or a server, with
/// the few values every cell draws. Cells take this instead of the model,
/// so books and server publications look and behave the same.
struct PublicationItem: Identifiable {
    enum Source {
        case local(Book)
        case remote(RemotePublication)
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
        subtitle = showsSeries ? publication.seriesTitle : nil
        self.cover = cover
        self.status = status
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
