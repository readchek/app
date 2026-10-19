import ChekReader
import Foundation
import SwiftData

/// A publication imported into the on-device library.
@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    /// The authors joined for display, empty when the publication names none.
    var authors: String
    /// The format's display name, such as "EPUB".
    var formatName: String
    /// The file's name inside the book's folder. The folder is found from
    /// `id` at run time because the app container's path changes between
    /// installs.
    var fileName: String
    var hasCover: Bool
    var addedAt: Date
    var lastOpenedAt: Date?
    /// When the book was added or last opened, which orders the library.
    var recentAt: Date
    /// The last reading position as Readium-compatible Locator JSON.
    var location: Data?
    /// Progress through the whole book, from 0 to 1, once it's known.
    var progress: Double?

    init(_ imported: ImportedBook) {
        id = imported.id
        title = imported.title
        authors = imported.authors
        formatName = imported.formatName
        fileName = imported.fileName
        hasCover = imported.hasCover
        addedAt = .now
        recentAt = .now
    }

    var fileURL: URL {
        LibraryFiles.folder(for: id).appending(path: fileName)
    }

    var coverURL: URL? {
        hasCover ? LibraryFiles.coverURL(for: id) : nil
    }

    var savedLocation: Locator? {
        get { location.flatMap { try? JSONDecoder().decode(Locator.self, from: $0) } }
        set {
            location = newValue.flatMap { try? JSONEncoder().encode($0) }
            if let total = newValue?.locations.totalProgression {
                progress = total
            }
        }
    }
}
