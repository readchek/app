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
        let id = book.id
        context.delete(book)
        save()
        LibraryFiles.remove(id)
    }

    func markFinished(_ book: Book) {
        book.finishedAt = .now
        book.progress = 1
        save()
    }

    /// Clears the book's place, so it reads as new.
    func markUnread(_ book: Book) {
        book.finishedAt = nil
        book.progress = nil
        book.location = nil
        book.lastOpenedAt = nil
        save()
    }

    /// The book with `id`, if it's still in the library.
    func book(_ id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
