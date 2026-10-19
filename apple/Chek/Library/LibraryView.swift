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
            LibraryContent(sort: sort, filter: $filter, search: search, layout: layout)
                .navigationTitle("Library")
                .searchable(text: $search, prompt: Text("Titles and Authors"))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        LibraryOptionsMenu(sort: $sort, layout: $layout)
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
    @Binding var layout: LibraryLayout

    var body: some View {
        Menu("View Options", systemImage: "line.3.horizontal.decrease") {
            Picker("Layout", selection: $layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.inline)
            Picker("Sort By", selection: $sort) {
                ForEach(LibrarySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// The books matching the current options. Its query is built from them,
/// so changing an option swaps the query rather than filtering in memory.
private struct LibraryContent: View {
    let layout: LibraryLayout
    @Binding var filter: LibraryFilter
    let isSearching: Bool
    @Query private var books: [Book]
    @State private var bookToRemove: Book?

    init(sort: LibrarySort, filter: Binding<LibraryFilter>, search: String, layout: LibraryLayout) {
        self.layout = layout
        _filter = filter
        isSearching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        _books = Query(filter: Book.predicate(kind: filter.wrappedValue.kind, search: search), sort: sort.descriptors, animation: .smooth)
    }

    var body: some View {
        Group {
            if books.isEmpty && !isSearching && filter == .all {
                EmptyLibraryView()
            } else {
                switch layout {
                case .grid:
                    LibraryGrid(books: books, filter: $filter, bookToRemove: $bookToRemove)
                case .list:
                    LibraryList(books: books, filter: $filter, bookToRemove: $bookToRemove)
                }
            }
        }
        .overlay {
            if books.isEmpty && isSearching {
                ContentUnavailableView.search
            } else if books.isEmpty && filter != .all {
                ContentUnavailableView(
                    filter == .comics ? "No Comics" : "No Books",
                    systemImage: filter == .comics ? "book.pages" : "book.closed",
                    description: Text("Add files from the Files app, or drop them here.")
                )
            }
        }
        .removeBookConfirmation(book: $bookToRemove)
    }
}

/// All, Books and Comics.
private struct LibraryFilterPicker: View {
    @Binding var filter: LibraryFilter

    var body: some View {
        Picker("Show", selection: $filter) {
            ForEach(LibraryFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct LibraryGrid: View {
    let books: [Book]
    @Binding var filter: LibraryFilter
    @Binding var bookToRemove: Book?

    var body: some View {
        ScrollView {
            LibraryFilterPicker(filter: $filter)
                .padding(.horizontal)
                .padding(.bottom, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20, alignment: .bottom)], spacing: 28) {
                ForEach(books) { book in
                    BookGridItem(book: book, bookToRemove: $bookToRemove)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}

private struct LibraryList: View {
    let books: [Book]
    @Binding var filter: LibraryFilter
    @Binding var bookToRemove: Book?

    var body: some View {
        List {
            LibraryFilterPicker(filter: $filter)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(books) { book in
                BookRow(book: book, bookToRemove: $bookToRemove)
            }
        }
        .listStyle(.plain)
    }
}

/// Shown until the first book is added.
private struct EmptyLibraryView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("Your Library", systemImage: "books.vertical")
        } description: {
            Text("Add EPUB, PDF, comics, MOBI, FictionBook, text and Markdown files from Files, or drop them here. They stay on this device and need no account.")
        } actions: {
            Button("Add Books") {
                router.addBooks()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}
