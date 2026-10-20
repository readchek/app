import ChekReader
import Foundation

/// A chapter on one of a server's sources, with what's needed to open it
/// and to list it in your places.
nonisolated struct SourceChapterRef: Hashable, Sendable {
    let server: UUID
    /// The extension's id.
    let source: String
    let seriesID: String
    let seriesTitle: String
    let chapterID: String
    let chapterTitle: String
    /// Whether the source says the series reads right to left, as manga do.
    var isRightToLeft = false
    /// The series' cover, a path on the server.
    var seriesCoverPath: String?

    var ref: PublicationRef { .source(server, source, chapterID) }
}

extension SourceChapterRef {
    /// The chapter a saved place is in, for opening it again.
    init(_ state: SourceReadingState) {
        self.init(
            server: state.serverID,
            source: state.sourceID,
            seriesID: state.seriesID,
            seriesTitle: state.seriesTitle,
            chapterID: state.chapterID,
            chapterTitle: state.chapterTitle,
            isRightToLeft: state.isRightToLeft,
            seriesCoverPath: state.seriesCoverPath
        )
    }
}

/// Streams a source chapter's pages through the server, which fetches
/// each from the source's site and caches it.
///
/// The page list is asked for while the reader opens, behind its loading
/// indicator, rather than before, so tapping a chapter opens the reader at
/// once however slow the source's site is.
nonisolated struct SourcePageSource: PageSource {
    let server: ServerAccess
    let chapter: SourceChapterRef
    let readingProgression: Publication.ReadingProgression
    private let list: PageList

    init(server: ServerAccess, chapter: SourceChapterRef, readingProgression: Publication.ReadingProgression) {
        self.server = server
        self.chapter = chapter
        self.readingProgression = readingProgression
        list = PageList(server: server, chapter: chapter)
    }

    func pageCount() async throws -> Int {
        // Downloaded chapters read from the device, offline or not.
        if let count = ChapterFiles.downloadedPageCount(of: chapter) {
            return count
        }
        let pages = try await list.pages()
        guard !pages.isEmpty else {
            throw DisplayError(title: String(localized: "This chapter has no pages."), message: String(localized: "The source didn't list any. It may not be out yet."))
        }
        return pages.count
    }

    func page(at index: Int) async throws -> Data {
        if ChapterFiles.downloadedPageCount(of: chapter) != nil {
            return try Data(contentsOf: ChapterFiles.page(index, of: chapter))
        }
        let pages = try await list.pages()
        let client = try await server.client()
        guard pages.indices.contains(index), let request = client.imageRequest(pages[index]) else {
            throw ChekError.notFound
        }
        return try await server.data(for: request)
    }

    /// The chapter's page paths, fetched once and shared by every page.
    private actor PageList {
        let server: ServerAccess
        let chapter: SourceChapterRef
        private var task: Task<[String], any Error>?

        init(server: ServerAccess, chapter: SourceChapterRef) {
            self.server = server
            self.chapter = chapter
        }

        func pages() async throws -> [String] {
            if let task {
                return try await task.value
            }
            let server = server
            let chapter = chapter
            let task = Task<[String], any Error> {
                try await server.request { client throws(ChekError) in
                    try await client.pages(ofChapter: chapter.chapterID, inSource: chapter.source)
                }
                .map(\.url)
            }
            self.task = task
            do {
                return try await task.value
            } catch {
                // A failed list can be asked for again, as when you retry.
                self.task = nil
                throw error
            }
        }
    }
}
