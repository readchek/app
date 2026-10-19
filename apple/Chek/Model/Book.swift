import ChekReader
import Foundation
import SwiftData

extension ChekSchemaV1 {
    /// A publication imported into the on-device library.
    ///
    /// Only ``LibraryStore`` and ``ProgressStore`` change books. Views read
    /// them, usually through `@Query`.
    @Model
    final class Book {
        @Attribute(.unique) var id: UUID
        var title: String
        /// The authors joined for display, empty when the publication names none.
        var authors: String
        /// The format's display name, such as "EPUB".
        var formatName: String
        /// ``PublicationKind`` as stored.
        var kindRawValue: String
        var seriesTitle: String?
        var seriesPosition: Double?
        /// The file's name inside the book's folder. The folder is found from
        /// `id` at run time because the app container's path changes between
        /// installs.
        var fileName: String
        var fileSize: Int64
        var hasCover: Bool
        var addedAt: Date
        var lastOpenedAt: Date?
        /// When the book was added or last opened, which orders the library.
        var recentAt: Date
        /// The last reading position as Readium-compatible Locator JSON.
        var location: Data?
        /// Progress through the whole book, from 0 to 1, once it's known.
        var progress: Double?
        var finishedAt: Date?

        init(_ imported: ImportedBook, at date: Date = .now) {
            id = imported.id
            title = imported.title
            authors = imported.authors
            formatName = imported.formatName
            kindRawValue = imported.kind.rawValue
            seriesTitle = imported.seriesTitle
            seriesPosition = imported.seriesPosition
            fileName = imported.fileName
            fileSize = imported.fileSize
            hasCover = imported.hasCover
            location = imported.location
            progress = imported.progress
            addedAt = date
            recentAt = date
        }

        var kind: PublicationKind {
            PublicationKind(rawValue: kindRawValue) ?? .book
        }

        var ref: PublicationRef {
            .local(id)
        }

        var fileURL: URL {
            LibraryFiles.folder(for: id).appending(path: fileName)
        }

        var coverURL: URL? {
            hasCover ? LibraryFiles.coverURL(for: id) : nil
        }

        var savedLocation: Locator? {
            location.flatMap { try? JSONDecoder().decode(Locator.self, from: $0) }
        }

        var readingStatus: ReadingStatus {
            ReadingStatus(progress: progress, finished: finishedAt != nil, opened: lastOpenedAt != nil)
        }
    }
}
