import Foundation

/// The books someone imported into Chibi Manga, which Chek replaces as an
/// update with the same bundle id, so they're still in the app's Documents
/// folder after updating.
///
/// Chibi Manga kept them in `Documents/imports`, listed in
/// `.library.json` with the page each was left on. Chek moves each book
/// into its own library once, then renames the list so it isn't read again.
nonisolated enum ChibiMangaLibrary {
    /// One book as Chibi Manga listed it. Only what Chek carries over is
    /// decoded, so other fields changing between versions doesn't matter.
    struct Entry: Decodable, Sendable {
        var fileName: String
        /// Zero-based.
        var currentPage: Int
        /// Seconds since 2001, as `JSONEncoder` writes dates by default.
        var lastReadAt: Date?
    }

    static var folder: URL {
        URL.documentsDirectory.appending(path: "imports", directoryHint: .isDirectory)
    }

    private static var list: URL {
        folder.appending(path: ".library.json")
    }

    /// The books still waiting to be carried over, whose files exist, or
    /// none once they have been.
    static func pendingEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: list),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.filter { FileManager.default.fileExists(atPath: file(for: $0).path) }
    }

    /// Where an entry's book is now. Chibi Manga stored absolute paths, which
    /// point into the old app container, so the file is found by name.
    static func file(for entry: Entry) -> URL {
        folder.appending(path: entry.fileName)
    }

    /// Marks the list as carried over. It's renamed rather than deleted, so
    /// a book that couldn't be read stays on the device with its place on
    /// record.
    static func finish() {
        let done = folder.appending(path: ".library.imported-into-chek.json")
        try? FileManager.default.removeItem(at: done)
        try? FileManager.default.moveItem(at: list, to: done)
    }
}
