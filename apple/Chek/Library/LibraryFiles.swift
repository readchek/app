import Foundation

/// Where imported books live: one folder per book in Application Support,
/// holding the book's file and its cover thumbnail.
nonisolated enum LibraryFiles {
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
    }

    static func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    static func coverURL(for id: UUID) -> URL {
        folder(for: id).appending(path: "cover.jpg")
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }
}
