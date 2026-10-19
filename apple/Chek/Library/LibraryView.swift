import SwiftData
import SwiftUI

/// The books on this device, most recently read first.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.recentAt, order: .reverse) private var books: [Book]
    @State private var isImporting = false
    @State private var importsInProgress = 0
    @State private var failures: [ImportFailure] = []

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyLibrary
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 20, alignment: .top)], spacing: 28) {
                            ForEach(books) { book in
                                NavigationLink(value: book) {
                                    BookCell(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                                        remove(book)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Book.self) { book in
                ReaderScreen(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if importsInProgress > 0 {
                        ProgressView()
                    } else {
                        Button("Add Books", systemImage: "plus") {
                            isImporting = true
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: BookImporter.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importBooks(urls)
            case .failure(let error):
                failures = [ImportFailure(fileName: nil, message: error.localizedDescription)]
            }
        }
        .onOpenURL { url in
            importBooks([url])
        }
        .alert(
            "Some books couldn't be added",
            isPresented: Binding { !failures.isEmpty } set: { if !$0 { failures = [] } }
        ) {
            Button("OK") {}
        } message: {
            Text(failures.map(\.description).joined(separator: "\n\n"))
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Add EPUB, PDF, comics, MOBI, FictionBook, text or Markdown files from Files.")
        } actions: {
            Button("Add Books") {
                isImporting = true
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func importBooks(_ urls: [URL]) {
        importsInProgress += urls.count
        for url in urls {
            Task {
                defer { importsInProgress -= 1 }
                do {
                    let imported = try await BookImporter.importBook(from: url)
                    modelContext.insert(Book(imported))
                } catch {
                    failures.append(ImportFailure(fileName: url.lastPathComponent, message: error.localizedDescription))
                }
            }
        }
    }

    private func remove(_ book: Book) {
        LibraryFiles.remove(book.id)
        modelContext.delete(book)
    }
}

private struct ImportFailure: CustomStringConvertible {
    var fileName: String?
    var message: String

    var description: String {
        if let fileName { "\(fileName): \(message)" } else { message }
    }
}
