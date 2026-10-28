import Foundation
import Observation
import SwiftData

/// Owns every change to the on-device library: importing, removing and
/// marking books. Views read books with `@Query` and come here to change them.
@MainActor
@Observable
final class LibraryStore {
    /// A file being added to the library.
    struct Import: Identifiable, Equatable {
        let id = UUID()
        let fileName: String
    }

    /// Imports that haven't finished, oldest first.
    private(set) var imports: [Import] = []
    /// Files that couldn't be added since the last time they were shown.
    var failures: [ImportFailure] = []

    /// Whether ``failures`` are being shown. Dismissing them clears them.
    var isShowingFailures: Bool {
        get { !failures.isEmpty }
        set { if !newValue { failures = [] } }
    }

    /// ``failures`` as one message.
    var failureSummary: String {
        failures.map { failure in
            [failure.fileName, failure.error.title, failure.error.message].compactMap(\.self).joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private let context: ModelContext
    @ObservationIgnored private var hasCarriedOver = false

    init(context: ModelContext) {
        self.context = context
    }

    /// Copies each file into the library. Files that can't be read are
    /// reported in ``failures`` and leave nothing behind.
    func importBooks(from urls: [URL]) {
        for url in urls {
            let job = Import(fileName: url.lastPathComponent)
            imports.append(job)
            Task {
                defer { imports.removeAll { $0.id == job.id } }
                do {
                    let imported = try await BookImporter.importBook(from: url)
                    context.insert(Book(imported))
                    save()
                } catch {
                    failures.append(ImportFailure(fileName: job.fileName, error: DisplayError(error)))
                }
            }
        }
    }

    /// Moves the books someone had in Chibi Manga into the library, each
    /// at the page they left it on. It runs once, on the first launch
    /// after updating; books that can't be read are left where they were.
    func carryOverChibiMangaLibrary() async {
        // Each window asks, and only the first should carry anything over.
        guard !hasCarriedOver else { return }
        hasCarriedOver = true
        let entries = ChibiMangaLibrary.pendingEntries()
        guard !entries.isEmpty else { return }
        let jobs = entries.map { Import(fileName: $0.fileName) }
        imports.append(contentsOf: jobs)
        // One at a time, so a large library doesn't open every book at once.
        for (entry, job) in zip(entries, jobs) {
            defer { imports.removeAll { $0.id == job.id } }
            let imported: ImportedBook
            do {
                imported = try await BookImporter.importBook(
                    from: ChibiMangaLibrary.file(for: entry),
                    moving: true,
                    page: entry.currentPage
                )
            } catch {
                // Said once, like a failed import, rather than vanishing.
                failures.append(ImportFailure(fileName: entry.fileName, error: DisplayError(error)))
                continue
            }
            let book = Book(imported, at: entry.lastReadAt ?? .now)
            // A page kept in Chibi Manga means it was being read, even for
            // books whose pages don't map to a place here.
            if entry.currentPage > 0 {
                book.lastOpenedAt = entry.lastReadAt ?? .now
            }
            context.insert(book)
            save()
        }
        ChibiMangaLibrary.finish()
    }

    func remove(_ book: Book) {
        remove([book])
    }

    func remove(_ books: [Book]) {
        let ids = books.map(\.id)
        for book in books {
            context.delete(book)
        }
        save()
        for id in ids {
            LibraryFiles.remove(id)
        }
    }

    func markFinished(_ book: Book) {
        markFinished([book])
    }

    func markFinished(_ books: [Book]) {
        for book in books {
            book.finishedAt = .now
            book.progress = 1
        }
        save()
    }

    /// Clears the book's place, so it reads as new.
    func markUnread(_ book: Book) {
        markUnread([book])
    }

    func markUnread(_ books: [Book]) {
        for book in books {
            book.finishedAt = nil
            book.progress = nil
            book.location = nil
            book.lastOpenedAt = nil
        }
        save()
    }

    /// The book with `id`, if it's still in the library.
    func book(_ id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The books either side of `book` in its series on this device, by
    /// their place in the series, then by title for books without one.
    /// Nil each way at either end, and both ways for a book in no series.
    func neighbors(of book: Book) -> (previous: Book?, next: Book?) {
        guard let series = book.seriesTitle, !series.isEmpty else { return (nil, nil) }
        let wanted: String? = series
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.seriesTitle == wanted })
        let books = ((try? context.fetch(descriptor)) ?? []).sorted { first, second in
            switch (first.seriesPosition, second.seriesPosition) {
            case let (a?, b?) where a != b: a < b
            case (.some, nil): true
            case (nil, .some): false
            default: first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
        }
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return (nil, nil) }
        return (
            index > books.startIndex ? books[index - 1] : nil,
            index + 1 < books.endIndex ? books[index + 1] : nil
        )
    }

    private func save() {
        // A failed save leaves the change in the context, and SwiftData
        // tries again with the next save or its autosave.
        try? context.save()
    }
}

/// A file that couldn't be added to the library, and why.
struct ImportFailure: Identifiable, Hashable {
    let id = UUID()
    var fileName: String
    var error: DisplayError
}
