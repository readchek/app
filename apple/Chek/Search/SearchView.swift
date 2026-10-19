import SwiftData
import SwiftUI

/// Looks through everything at once.
struct SearchView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            SearchResults(text: text)
                .navigationTitle("Search")
        }
        .searchable(text: $text, prompt: Text("Books, Comics and Authors"))
    }
}

private struct SearchResults: View {
    let text: String
    @Query private var books: [Book]

    init(text: String) {
        self.text = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<Book>(
            predicate: Book.predicate(kind: nil, search: trimmed),
            sortBy: [SortDescriptor(\.title, comparator: .localizedStandard)]
        )
        // An empty search would list the whole library.
        descriptor.fetchLimit = trimmed.isEmpty ? 0 : 50
        _books = Query(descriptor)
    }

    var body: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search Your Library", systemImage: "magnifyingglass", description: Text("Find books and comics by title or author."))
        } else if books.isEmpty {
            ContentUnavailableView.search(text: text)
        } else {
            List {
                Section("On This Device") {
                    ForEach(books) { book in
                        SearchBookRow(book: book)
                    }
                }
            }
        }
    }
}

private struct SearchBookRow: View {
    let book: Book
    @State private var bookToRemove: Book?

    var body: some View {
        BookRow(book: book, bookToRemove: $bookToRemove)
            .removeBookConfirmation(book: $bookToRemove)
    }
}
