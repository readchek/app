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

    var ref: PublicationRef { .source(server, source, chapterID) }
}

/// Streams a source chapter's pages through the server, which fetches
/// each from the source's site and caches it.
nonisolated struct SourcePageSource: PageSource {
    let client: ChekClient
    /// The server paths of the pages, in reading order.
    let pages: [String]

    func pageCount() async throws -> Int {
        pages.count
    }

    func page(at index: Int) async throws -> Data {
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
}
