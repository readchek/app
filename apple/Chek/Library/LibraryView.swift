import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The books and comics on this device.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("library.sort") private var sort = LibrarySort.recent
    @AppStorage("library.filter") private var filter = LibraryFilter.all
    @AppStorage("library.layout") private var layout = LibraryLayout.grid

    var body: some View {
        NavigationStack {
            // Searching is the Search tab's, which covers this library too,
            // so there's one place to search rather than two side by side.
            LibraryContent(sort: sort, filter: filter, layout: layout)
                .navigationTitle(Text(filter.navigationTitle))
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
    @Query private var books: [Book]
    @State private var bookToRemove: Book?
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(sort: LibrarySort, filter: LibraryFilter, layout: LibraryLayout) {
        self.filter = filter
        self.layout = layout
        _books = Query(filter: Book.predicate(kind: filter.kind, search: "", finishedOnly: filter == .finished), sort: sort.descriptors, animation: .default)
    }

    var body: some View {
        Group {
            if books.isEmpty {
                if filter == .finished {
                    ContentUnavailableView("Nothing Finished Yet", systemImage: "checkmark.circle", description: Text("Books you finish, or mark as finished, collect here."))
                } else if filter != .all {
                    ContentUnavailableView(filter == .comics ? "No Comics" : "No Books", systemImage: "books.vertical")
                } else {
                    EmptyLibraryView()
                }
            } else {
                switch layout {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
                            ForEach(books) { book in
                                let item = PublicationItem(book)
                                PublicationCell(item: item)
                                    .contextMenu {
                                        BookActions(book: book, bookToRemove: $bookToRemove)
                                    } preview: {
                                        // The cover alone lifts, as in Books,
                                        // rather than the cell and its caption.
                                        CoverView(source: item.cover, title: item.title, isFramed: false)
                                            .frame(width: 240)
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
                            // Not a destructive role: that removes the row at
                            // once, before you've confirmed, and the list then
                            // disagrees with the books it shows.
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Remove", systemImage: "trash") {
                                    bookToRemove = book
                                }
                                .tint(.red)
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
