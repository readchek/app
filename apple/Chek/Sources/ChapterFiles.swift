import Foundation

/// Where downloaded source chapters live: one folder per chapter under
/// Application Support, since you chose to keep them.
nonisolated enum ChapterFiles {
    static let root = URL.applicationSupportDirectory.appending(path: "Chapters", directoryHint: .isDirectory)

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

    static func folder(for server: UUID) -> URL {
        root.appending(path: server.uuidString, directoryHint: .isDirectory)
    }

    static func folder(for chapter: SourceChapterRef) -> PageFolder {
        // Source and chapter ids are the source's own, so they're kept to
        // safe file names.
        PageFolder(url: folder(for: chapter.server)
            .appending(path: PageFolder.hex(chapter.source), directoryHint: .isDirectory)
            .appending(path: PageFolder.hex(chapter.chapterID), directoryHint: .isDirectory))
    }

    /// How many pages the chapter has, when it's fully downloaded.
    static func downloadedPageCount(of chapter: SourceChapterRef) -> Int? {
        folder(for: chapter).downloadedPageCount
    }

    static func page(_ index: Int, of chapter: SourceChapterRef) -> URL {
        folder(for: chapter).page(index)
    }

    static func markComplete(_ chapter: SourceChapterRef, pageCount: Int) throws {
        try folder(for: chapter).markComplete(Note(chapter, pageCount: pageCount), pageCount: pageCount)
    }

    static func removeAll(for server: UUID) {
        try? FileManager.default.removeItem(at: folder(for: server))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Every chapter that's fully downloaded, found by walking the folders
    /// once at launch. One cut off partway is dropped on the way.
    static func downloaded() -> [SourceChapterRef] {
        var found: [SourceChapterRef] = []
        let manager = FileManager.default
        for serverFolder in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard let server = UUID(uuidString: serverFolder.lastPathComponent) else { continue }
            for sourceFolder in (try? manager.contentsOfDirectory(at: serverFolder, includingPropertiesForKeys: nil)) ?? [] {
                guard let source = unhex(sourceFolder.lastPathComponent) else { continue }
                for folder in PageFolder.completed(under: sourceFolder) {
                    guard let chapter = unhex(folder.url.lastPathComponent), let note = folder.readNote(Note.self) else {
                        folder.remove()
                        continue
                    }
                    found.append(SourceChapterRef(
                        server: server,
                        source: source,
                        seriesID: note.seriesID,
                        seriesTitle: note.seriesTitle,
                        chapterID: chapter,
                        chapterTitle: note.chapterTitle,
                        isRightToLeft: note.isRightToLeft,
                        seriesCoverPath: note.seriesCoverPath
                    ))
                }
            }
        }
        return found
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

/// Where downloaded server comics live: one folder per publication under
/// Application Support, beside the chapters.
nonisolated enum PublicationFiles {
    static let root = URL.applicationSupportDirectory.appending(path: "Publications", directoryHint: .isDirectory)

    static func folder(for server: UUID) -> URL {
        root.appending(path: server.uuidString, directoryHint: .isDirectory)
    }

    static func folder(for publication: RemotePublication) -> PageFolder {
        folder(for: publication.id, on: publication.server)
    }

    static func folder(for publication: Int64, on server: UUID) -> PageFolder {
        PageFolder(url: folder(for: server).appending(path: String(publication), directoryHint: .isDirectory))
    }

    static func markComplete(_ publication: RemotePublication, pageCount: Int) throws {
        try folder(for: publication).markComplete(publication, pageCount: pageCount)
    }

    static func removeAll(for server: UUID) {
        try? FileManager.default.removeItem(at: folder(for: server))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Every comic that's fully downloaded, as the publication it was
    /// listed as, found by walking the folders once at launch.
    static func downloaded() -> [RemotePublication] {
        var found: [RemotePublication] = []
        for serverFolder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard UUID(uuidString: serverFolder.lastPathComponent) != nil else { continue }
            for folder in PageFolder.completed(under: serverFolder) {
                guard let publication = folder.readNote(RemotePublication.self) else {
                    folder.remove()
                    continue
                }
                found.append(publication)
            }
        }
        return found
    }
}
