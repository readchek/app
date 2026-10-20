import Foundation

/// Where downloaded source chapters live: one folder per chapter under
/// Application Support, since you chose to keep them, with a page per
/// file and a marker once every page is there.
nonisolated enum ChapterFiles {
    static let root = URL.applicationSupportDirectory.appending(path: "Chapters", directoryHint: .isDirectory)

    static func folder(for server: UUID) -> URL {
        root.appending(path: server.uuidString, directoryHint: .isDirectory)
    }

    static func folder(for chapter: SourceChapterRef) -> URL {
        // Source and chapter ids are the source's own, so they're kept to
        // safe file names.
        folder(for: chapter.server)
            .appending(path: hex(chapter.source), directoryHint: .isDirectory)
            .appending(path: hex(chapter.chapterID), directoryHint: .isDirectory)
    }

    static func page(_ index: Int, of chapter: SourceChapterRef) -> URL {
        folder(for: chapter).appending(path: String(format: "%04d.img", index))
    }

    /// What's known about a downloaded chapter beyond its pages: enough
    /// to list it and its series without the server.
    struct Note: Codable, Hashable, Sendable {
        var seriesID: String
        var seriesTitle: String
        var chapterTitle: String
        var isRightToLeft: Bool
        var seriesCoverPath: String?
        var pageCount: Int

        init(_ chapter: SourceChapterRef, pageCount: Int) {
            seriesID = chapter.seriesID
            seriesTitle = chapter.seriesTitle
            chapterTitle = chapter.chapterTitle
            isRightToLeft = chapter.isRightToLeft
            seriesCoverPath = chapter.seriesCoverPath
            self.pageCount = pageCount
        }
    }

    /// The marker written last, holding the page count, so a chapter is
    /// downloaded only once every page is.
    private static func marker(for chapter: SourceChapterRef) -> URL {
        folder(for: chapter).appending(path: "complete")
    }

    private static func noteURL(in folder: URL) -> URL {
        folder.appending(path: "chapter.json")
    }

    /// How many pages the chapter has, when it's fully downloaded.
    static func downloadedPageCount(of chapter: SourceChapterRef) -> Int? {
        guard let text = try? String(contentsOf: marker(for: chapter), encoding: .utf8) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func markComplete(_ chapter: SourceChapterRef, pageCount: Int) throws {
        let note = try JSONEncoder().encode(Note(chapter, pageCount: pageCount))
        try note.write(to: noteURL(in: folder(for: chapter)), options: .atomic)
        try String(pageCount).write(to: marker(for: chapter), atomically: true, encoding: .utf8)
    }

    static func remove(_ chapter: SourceChapterRef) {
        try? FileManager.default.removeItem(at: folder(for: chapter))
    }

    static func removeAll(for server: UUID) {
        try? FileManager.default.removeItem(at: folder(for: server))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Every chapter that's fully downloaded, as a chapter reference with
    /// its note, found by walking the folders once at launch. A chapter
    /// folder with no marker was cut off partway, by the app being killed,
    /// and goes.
    static func downloaded() -> [SourceChapterRef: Note] {
        var found: [SourceChapterRef: Note] = [:]
        let manager = FileManager.default
        let decoder = JSONDecoder()
        for serverFolder in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard let server = UUID(uuidString: serverFolder.lastPathComponent) else { continue }
            for sourceFolder in (try? manager.contentsOfDirectory(at: serverFolder, includingPropertiesForKeys: nil)) ?? [] {
                guard let source = unhex(sourceFolder.lastPathComponent) else { continue }
                for chapterFolder in (try? manager.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil)) ?? [] {
                    guard manager.fileExists(atPath: chapterFolder.appending(path: "complete").path(percentEncoded: false)),
                          let data = try? Data(contentsOf: noteURL(in: chapterFolder)),
                          let note = try? decoder.decode(Note.self, from: data)
                    else {
                        try? manager.removeItem(at: chapterFolder)
                        continue
                    }
                    guard let chapter = unhex(chapterFolder.lastPathComponent) else { continue }
                    found[SourceChapterRef(
                        server: server,
                        source: source,
                        seriesID: note.seriesID,
                        seriesTitle: note.seriesTitle,
                        chapterID: chapter,
                        chapterTitle: note.chapterTitle,
                        isRightToLeft: note.isRightToLeft,
                        seriesCoverPath: note.seriesCoverPath
                    )] = note
                }
            }
        }
        return found
    }

    private static func hex(_ text: String) -> String {
        Data(text.utf8).map { String(format: "%02x", $0) }.joined()
    }

    private static func unhex(_ name: String) -> String? {
        guard name.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = name.startIndex
        while index < name.endIndex {
            let next = name.index(index, offsetBy: 2)
            guard let byte = UInt8(name[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
