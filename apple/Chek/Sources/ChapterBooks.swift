import CryptoKit
import Foundation

/// Where books read from sources are kept once fetched: one folder per
/// chapter in Caches, holding the file under the source's id for it and the
/// rights it came with. A changed file gets a new id, so a file that's here
/// is current, and the last one fetched still opens offline.
nonisolated enum ChapterBooks {
    static let root = URL.cachesDirectory.appending(path: "ChapterBooks", directoryHint: .isDirectory)

    static func folder(for chapter: SourceChapterRef) -> URL {
        // Ids are the source's own, so they're kept to safe file names.
        root.appending(path: chapter.server.uuidString, directoryHint: .isDirectory)
            .appending(path: PageFolder.hex(chapter.source), directoryHint: .isDirectory)
            .appending(path: PageFolder.hex(chapter.chapterID), directoryHint: .isDirectory)
    }

    /// Where `file` is kept, named for the format the server gave rather
    /// than anything in its address.
    static func file(_ file: ChekAPI.RemoteFile, format: ChekAPI.ContentFormat, of chapter: SourceChapterRef) -> URL {
        // Hashed, since a source's id can be longer than a file name may be.
        let name = SHA256.hash(data: Data(file.id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return folder(for: chapter).appending(path: "\(name).\(format.rawValue)")
    }

    /// The book last fetched for `chapter`, with its format, for reading
    /// it without the server.
    static func kept(for chapter: SourceChapterRef) -> (url: URL, format: ChekAPI.ContentFormat)? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(for: chapter), includingPropertiesForKeys: nil)) ?? []
        for url in files {
            if let format = ChekAPI.ContentFormat(rawValue: url.pathExtension), format != .images {
                return (url, format)
            }
        }
        return nil
    }

    /// Drops files of the chapter other than `keeping`, as when the source
    /// replaced the book.
    static func removeOthers(of chapter: SourceChapterRef, keeping: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(for: chapter), includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent != keeping.lastPathComponent && url.pathExtension != "json" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func saveRights(_ rights: ChekAPI.Rights?, of chapter: SourceChapterRef) {
        let url = folder(for: chapter).appending(path: "rights.json")
        guard let rights, !rights.isEmpty, let data = try? JSONEncoder().encode(rights) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: folder(for: chapter), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func rights(of chapter: SourceChapterRef) -> ChekAPI.Rights? {
        guard let data = try? Data(contentsOf: folder(for: chapter).appending(path: "rights.json")) else { return nil }
        return try? JSONDecoder().decode(ChekAPI.Rights.self, from: data)
    }

    static func removeAll(for server: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: server.uuidString, directoryHint: .isDirectory))
    }
}
