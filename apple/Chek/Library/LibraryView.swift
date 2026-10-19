import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The books and comics on this device.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("library.sort") private var sort = LibrarySort.recent
    @AppStorage("library.filter") private var filter = LibraryFilter.all
    @AppStorage("library.layout") private var layout = LibraryLayout.grid
    @State private var search = ""

    var body: some View {
        NavigationStack {
            LibraryContent(sort: sort, filter: filter, search: search, layout: layout)
                .navigationTitle(Text(filter.navigationTitle))
                .searchable(text: $search, prompt: Text("Titles and Authors"))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        LibraryOptionsMenu(sort: $sort, filter: $filter, layout: $layout)
                        AddBooksButton()
                    }
                }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            library.importBooks(from: files)
            return !files.isEmpty
        }
    }
}

/// The add button, which turns into a spinner while files are importing.
private struct AddBooksButton: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router

    var body: some View {
        if library.imports.isEmpty {
            Button("Add Books", systemImage: "plus") {
                router.addBooks()
            }
        } else {
            ProgressView()
                .accessibilityLabel(Text("Adding \(library.imports.count) books"))
        }
    }
}

private struct LibraryOptionsMenu: View {
    @Binding var sort: LibrarySort
    @Binding var filter: LibraryFilter
    @Binding var layout: LibraryLayout

    var body: some View {
        Menu("View Options", systemImage: "line.3.horizontal.decrease") {
            Picker("Show", selection: $filter) {
                ForEach(LibraryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.inline)
            Picker("Sort By", selection: $sort) {
                ForEach(LibrarySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.inline)
            Picker("Layout", selection: $layout) {
                Label("Grid", systemImage: "square.grid.3x2").tag(LibraryLayout.grid)
                Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.inline)
        }
    }
}

/// The books matching the current options. Its query is built from them,
/// so changing an option swaps the query rather than filtering in memory.
private struct LibraryContent: View {
    let filter: LibraryFilter
    let layout: LibraryLayout
    let isSearching: Bool
    @Query private var books: [Book]
    @State private var bookToRemove: Book?

    init(sort: LibrarySort, filter: LibraryFilter, search: String, layout: LibraryLayout) {
        self.filter = filter
        self.layout = layout
        isSearching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        _books = Query(filter: Book.predicate(kind: filter.kind, search: search), sort: sort.descriptors, animation: .default)
    }

    var body: some View {
        Group {
            if books.isEmpty {
                if isSearching {
                    ContentUnavailableView.search
                } else if filter != .all {
                    ContentUnavailableView(filter == .comics ? "No Comics" : "No Books", systemImage: "books.vertical")
                } else {
                    EmptyLibraryView()
                }
            } else {
                switch layout {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: Metrics.gridColumns, spacing: Metrics.gridRowSpacing) {
                            ForEach(books) { book in
                                PublicationCell(item: PublicationItem(book))
                                    .contextMenu {
                                        BookActions(book: book, bookToRemove: $bookToRemove)
                                    }
                                    .removeBookConfirmation(book: removal(of: book))
                            }
                        }
                        .padding(.horizontal, Metrics.margin)
                        .padding(.vertical, 8)
                    }
                case .list:
                    List(books) { book in
                        PublicationRow(item: PublicationItem(book))
                            .contextMenu {
                                BookActions(book: book, bookToRemove: $bookToRemove)
                            }
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    bookToRemove = book
                                }
                            }
                            .removeBookConfirmation(book: removal(of: book))
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    /// The book being removed, for `book`'s own cell only, so the question
    /// points at the book you chose rather than the middle of the screen.
    private func removal(of book: Book) -> Binding<Book?> {
        Binding {
            bookToRemove?.id == book.id ? bookToRemove : nil
        } set: {
            bookToRemove = $0
        }
    }
}

/// Shown until the first book is added.
private struct EmptyLibraryView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Add EPUB, PDF, comics, MOBI, FictionBook, text and Markdown files from Files, or drop them here. They stay on this device.")
        } actions: {
            Button("Add Books") {
                router.addBooks()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
