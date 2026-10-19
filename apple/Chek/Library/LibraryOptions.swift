import Foundation
import SwiftData

/// How the library is ordered.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, author, added

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .recent: "Recent"
        case .title: "Title"
        case .author: "Author"
        case .added: "Date Added"
        }
    }

    var descriptors: [SortDescriptor<Book>] {
        switch self {
        case .recent: [SortDescriptor(\.recentAt, order: .reverse)]
        case .title: [SortDescriptor(\.title, comparator: .localizedStandard)]
        case .author: [SortDescriptor(\.authors, comparator: .localizedStandard), SortDescriptor(\.title, comparator: .localizedStandard)]
        case .added: [SortDescriptor(\.addedAt, order: .reverse)]
        }
    }
}

/// Which kinds of publication the library shows.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, books, comics

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .books: "Books"
        case .comics: "Comics"
        }
    }

    var navigationTitle: LocalizedStringResource {
        switch self {
        case .all: "Library"
        case .books: "Books"
        case .comics: "Comics"
        }
    }

    var kind: PublicationKind? {
        switch self {
        case .all: nil
        case .books: .book
        case .comics: .comic
        }
    }
}

/// Covers in a grid, or rows in a list.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: Self { self }
}

extension Book {
    /// Books of `kind` whose title or authors contain `search`.
    static func predicate(kind: PublicationKind?, search: String) -> Predicate<Book> {
        let kindValue = kind?.rawValue ?? ""
        let anyKind = kind == nil
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let anyText = text.isEmpty
        return #Predicate<Book> { book in
            (anyKind || book.kindRawValue == kindValue)
                && (anyText || book.title.localizedStandardContains(text) || book.authors.localizedStandardContains(text))
        }
    }
}
