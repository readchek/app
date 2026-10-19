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
    let client: ChekClient
    let chapter: SourceChapterRef
    let readingProgression: Publication.ReadingProgression
    private let list: PageList

    init(client: ChekClient, chapter: SourceChapterRef, readingProgression: Publication.ReadingProgression) {
        self.client = client
        self.chapter = chapter
        self.readingProgression = readingProgression
        list = PageList(client: client, chapter: chapter)
    }

    func pageCount() async throws -> Int {
        let pages = try await list.pages()
        guard !pages.isEmpty else {
            throw DisplayError(title: String(localized: "This chapter has no pages."), message: String(localized: "The source didn't list any. It may not be out yet."))
        }
        return pages.count
    }

    func page(at index: Int) async throws -> Data {
        let pages = try await list.pages()
        guard pages.indices.contains(index), let request = client.imageRequest(pages[index]) else {
            throw ChekError.notFound
        }
        let (data, response) = try await client.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChekError.invalidResponse }
        switch http.statusCode {
        case 200: return data
        case 401: throw ChekError.unauthorized
        default: throw ChekError.server(status: http.statusCode, code: nil)
        }
    }

    /// The chapter's page paths, fetched once and shared by every page.
    private actor PageList {
        let client: ChekClient
        let chapter: SourceChapterRef
        private var task: Task<[String], any Error>?

        init(client: ChekClient, chapter: SourceChapterRef) {
            self.client = client
            self.chapter = chapter
        }

        func pages() async throws -> [String] {
            if let task {
                return try await task.value
            }
            let client = client
            let chapter = chapter
            let task = Task<[String], any Error> {
                try await client.pages(ofChapter: chapter.chapterID, inSource: chapter.source).map(\.url)
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
