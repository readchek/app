import Foundation

/// A folder holding a downloaded publication's pages, one file each, with
/// a marker written last so it counts as downloaded only once every page
/// is there, and a note of what it is so it can be listed without the
/// server.
nonisolated struct PageFolder: Hashable, Sendable {
    let url: URL

    func page(_ index: Int) -> URL {
        url.appending(path: String(format: "%04d.img", index))
    }

    private var marker: URL { url.appending(path: "complete") }
    private var note: URL { url.appending(path: "note.json") }

    /// How many pages are here, when all of them are.
    var downloadedPageCount: Int? {
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var isComplete: Bool {
        FileManager.default.fileExists(atPath: marker.path(percentEncoded: false))
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @concurrent
    func write(_ data: Data, page index: Int) async throws {
        try data.write(to: page(index), options: .atomic)
    }

    func markComplete<Note: Encodable>(_ note: Note, pageCount: Int) throws {
        try JSONEncoder().encode(note).write(to: self.note, options: .atomic)
        try String(pageCount).write(to: marker, atomically: true, encoding: .utf8)
    }

    func readNote<Note: Decodable>(_ type: Note.Type) -> Note? {
        guard isComplete, let data = try? Data(contentsOf: note) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// The folders directly under `root`, dropping any that isn't complete,
    /// which was cut off partway by the app being killed.
    static func completed(under root: URL) -> [PageFolder] {
        let manager = FileManager.default
        return ((try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let folder = PageFolder(url: url)
            guard folder.isComplete else {
                folder.remove()
                return nil
            }
            return folder
        }
    }

    static func hex(_ text: String) -> String {
        Data(text.utf8).map { String(format: "%02x", $0) }.joined()
    }
}
