import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The books and comics on this device.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("library.sort") private var sort = LibrarySort.recent
    @AppStorage("library.filter") private var filter = LibraryFilter.all
    @AppStorage("library.layout") private var layout = LibraryLayout.grid
    /// The books chosen while selecting, nil when not.
    @State private var selection: Set<UUID>?
    /// One book at most, only to know whether there's anything to select.
    @Query private var anyBook: [Book]

    init() {
        var descriptor = FetchDescriptor<Book>()
        descriptor.fetchLimit = 1
        _anyBook = Query(descriptor)
    }

    var body: some View {
        NavigationStack {
            // Searching is the Search tab's, which covers this library too,
            // so there's one place to search rather than two side by side.
            LibraryContent(sort: sort, filter: filter, layout: layout, selection: $selection)
                .demoBanner()
                .navigationTitle(selection.map { Text("^[\($0.count) Selected](inflect: true)") } ?? Text(filter.navigationTitle))
                .toolbar {
                    if selection != nil {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                withAnimation(.snappy) { selection = nil }
                            }
                        }
                    } else {
                        ToolbarItemGroup(placement: .primaryAction) {
                            LibraryOptionsMenu(sort: $sort, filter: $filter, layout: $layout, canSelect: !anyBook.isEmpty) {
                                withAnimation(.snappy) { selection = [] }
                            }
                            AddBooksButton()
                        }
                    }
                }
                .animation(.snappy, value: selection == nil)
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
    let canSelect: Bool
    let select: () -> Void

    var body: some View {
        Menu("View Options", systemImage: "line.3.horizontal.decrease") {
            Button("Select Books", systemImage: "checkmark.circle", action: select)
                .disabled(!canSelect)
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
    @Binding var selection: Set<UUID>?
    @Query private var books: [Book]
    @State private var bookToRemove: Book?
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(sort: LibrarySort, filter: LibraryFilter, layout: LibraryLayout, selection: Binding<Set<UUID>?>) {
        self.filter = filter
        self.layout = layout
        _selection = selection
        _books = Query(filter: Book.predicate(kind: filter.kind, search: "", finishedOnly: filter == .finished), sort: sort.descriptors, animation: .default)
    }

    var body: some View {
        content
            .toolbar {
                if let selection {
                    ToolbarItem(placement: .primaryAction) {
                        SelectionActions(books: books.filter { selection.contains($0.id) }, all: books, selection: $selection)
                    }
                }
            }
    }

    private var content: some View {
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
                                if selection != nil {
                                    PublicationCell(item: item)
                                        .selectable(book.id, in: $selection)
                                } else {
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
                        }
                        .padding(.horizontal, Metrics.margin)
                        .padding(.vertical, 8)
                    }
                case .list:
                    List(books, selection: Binding { selection ?? [] } set: { selection = selection == nil ? nil : $0 }) { book in
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
                    .environment(\.editMode, .constant(selection == nil ? .inactive : .active))
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

/// What can be done with the selected books, all at once.
private struct SelectionActions: View {
    let books: [Book]
    let all: [Book]
    @Binding var selection: Set<UUID>?
    @Environment(LibraryStore.self) private var library
    @State private var isConfirmingRemoval = false

    var body: some View {
        Menu("Actions", systemImage: "ellipsis.circle") {
            if books.count < all.count {
                Button("Select All", systemImage: "checkmark.circle") {
                    selection = Set(all.map(\.id))
                }
            } else {
                Button("Deselect All", systemImage: "circle") {
                    selection = []
                }
            }
            Divider()
            Button("Mark as Finished", systemImage: "checkmark.circle") {
                library.markFinished(books)
                selection = nil
            }
            .disabled(books.isEmpty || books.allSatisfy { $0.finishedAt != nil })
            Button("Mark as Unread", systemImage: "arrow.counterclockwise") {
                library.markUnread(books)
                selection = nil
            }
            .disabled(books.isEmpty || books.allSatisfy { $0.lastOpenedAt == nil && $0.finishedAt == nil })
            Divider()
            Button("Remove…", systemImage: "trash", role: .destructive) {
                isConfirmingRemoval = true
            }
            .disabled(books.isEmpty)
        }
        .confirmationDialog(
            "Remove ^[\(books.count) Book](inflect: true)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                library.remove(books)
                selection = nil
            }
        } message: {
            Text("Their files and your places in them are deleted from this device.")
        }
    }
}

extension View {
    /// Makes a grid cell pick `id` in and out of `selection` when tapped,
    /// instead of opening, and shows whether it's picked.
    fileprivate func selectable(_ id: UUID, in selection: Binding<Set<UUID>?>) -> some View {
        modifier(SelectableCell(id: id, selection: selection))
    }
}

private struct SelectableCell: ViewModifier {
    let id: UUID
    @Binding var selection: Set<UUID>?

    private var isSelected: Bool { selection?.contains(id) ?? false }

    func body(content: Content) -> some View {
        content
            .opacity(isSelected ? 1 : 0.7)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .shadow(radius: 1)
                    .padding(6)
            }
            // Over the cell, so the tap is this and not the open.
            .overlay {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            if isSelected {
                                selection?.remove(id)
                            } else {
                                selection?.insert(id)
                            }
                        }
                    }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
