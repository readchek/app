import ChekReader
import Foundation

/// Talks to one Chek server as one signed-in user.
///
/// A plain value with no state of its own, so it can be handed to any task.
/// ``ServerStore`` makes clients and notices when one's session ends.
nonisolated struct ChekClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    // MARK: - Signing in

    /// Checks that `baseURL` is a running Chek server.
    static func checkHealth(at baseURL: URL, session: URLSession = .shared) async throws(ChekError) {
        struct Health: Decodable { var status: String }
        let request = URLRequest(url: baseURL.appending(path: "health"), timeoutInterval: 10)
        let health: Health = try await send(request, session: session)
        guard health.status == "ok" else { throw .invalidResponse }
    }

    static func signIn(at baseURL: URL, name: String, password: String, device: String, session: URLSession = .shared) async throws(ChekError) -> ChekAPI.Session {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/auth/sign-in"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["name": name, "password": password, "device": device])
        return try await send(request, session: session)
    }

    /// The signed-in user, with their role.
    func currentUser() async throws(ChekError) -> ChekAPI.User {
        try await get("api/v1/me")
    }

    func signOut() async {
        var request = authorized("api/v1/auth/sign-out")
        request.httpMethod = "POST"
        _ = try? await session.data(for: request)
    }

    // MARK: - Catalog

    func libraries() async throws(ChekError) -> [ChekAPI.Library] {
        let page: ChekAPI.Items<ChekAPI.Library> = try await get("api/v1/libraries")
        return page.items
    }

    func series(inLibrary library: Int64, cursor: String?) async throws(ChekError) -> ChekAPI.Page<ChekAPI.Series> {
        try await get("api/v1/libraries/\(library)/series", cursor: cursor)
    }

    func publications(inSeries series: Int64, cursor: String?) async throws(ChekError) -> ChekAPI.Page<ChekAPI.PublicationSummary> {
        try await get("api/v1/series/\(series)/publications", cursor: cursor)
    }

    func recentlyAdded(cursor: String?) async throws(ChekError) -> ChekAPI.Page<ChekAPI.PublicationSummary> {
        try await get("api/v1/recently-added", cursor: cursor)
    }

    func continueReading() async throws(ChekError) -> [ChekAPI.ContinueReadingItem] {
        let page: ChekAPI.Page<ChekAPI.ContinueReadingItem> = try await get("api/v1/me/continue-reading", cursor: nil, limit: 20)
        return page.items
    }

    /// Searches the server, or only `library` when given.
    func search(_ text: String, inLibrary library: Int64? = nil, cursor: String?) async throws(ChekError) -> ChekAPI.Page<ChekAPI.PublicationSummary> {
        var query = [URLQueryItem(name: "q", value: String(text.prefix(200)))]
        if let library {
            query.append(URLQueryItem(name: "libraryId", value: String(library)))
        }
        return try await get("api/v1/search", query: query, cursor: cursor)
    }

    // MARK: - Sources

    func installedExtensions() async throws(ChekError) -> [ChekAPI.InstalledExtension] {
        let page: ChekAPI.Items<ChekAPI.InstalledExtension> = try await get("api/v1/me/extensions")
        return page.items
    }

    /// Installed extensions, or nil from a server too old to have them,
    /// which answers 404, so the rest of a screen can still show.
    func installedExtensionsIfSupported() async throws(ChekError) -> [ChekAPI.InstalledExtension]? {
        do {
            return try await installedExtensions()
        } catch .notFound {
            return nil
        }
    }

    func availableExtensions() async throws(ChekError) -> [ChekAPI.AvailableExtension] {
        let page: ChekAPI.Items<ChekAPI.AvailableExtension> = try await get("api/v1/extensions")
        return page.items
    }

    func extensionRepositories() async throws(ChekError) -> [ChekAPI.ExtensionRepository] {
        let page: ChekAPI.Items<ChekAPI.ExtensionRepository> = try await get("api/v1/extension-repositories")
        return page.items
    }

    /// Has the server read `repository`'s index again.
    func refresh(repository: Int64) async throws(ChekError) {
        var request = authorized("api/v1/extension-repositories/\(repository)/refresh")
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        try await Self.sendWithoutBody(request, session: session)
    }

    /// Adds a repository by what was typed: its address, the folder holding
    /// its `index.json`, or `github:owner/repo`. The server reads it first
    /// and refuses one it can't, so this can take a while.
    func addRepository(_ address: String, credentials: ChekAPI.RepositoryCredentials?) async throws(ChekError) -> ChekAPI.ExtensionRepository {
        struct Body: Encodable {
            var url: String
            var credentials: ChekAPI.RepositoryCredentials?
        }
        var request = authorized("api/v1/extension-repositories")
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(url: address, credentials: credentials))
        return try await Self.send(request, session: session)
    }

    /// Replaces `repository`'s credentials, or removes them when nil. The
    /// server refuses ones it can't read the repository with.
    func setCredentials(_ credentials: ChekAPI.RepositoryCredentials?, of repository: Int64) async throws(ChekError) -> ChekAPI.ExtensionRepository {
        struct Body: Encodable {
            var credentials: ChekAPI.RepositoryCredentials?

            // Null, not left out, says to remove them.
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(credentials, forKey: .credentials)
            }

            enum CodingKeys: String, CodingKey { case credentials }
        }
        var request = authorized("api/v1/extension-repositories/\(repository)")
        request.httpMethod = "PATCH"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(credentials: credentials))
        return try await Self.send(request, session: session)
    }

    /// Removes `repository` and every extension installed from it.
    func removeRepository(_ repository: Int64) async throws(ChekError) {
        var request = authorized("api/v1/extension-repositories/\(repository)")
        request.httpMethod = "DELETE"
        try await Self.sendWithoutBody(request, session: session)
    }

    func settings() async throws(ChekError) -> ChekAPI.ServerSettings {
        try await get("api/v1/settings")
    }

    func saveSettings(_ settings: ChekAPI.ServerSettings) async throws(ChekError) -> ChekAPI.ServerSettings {
        var request = authorized("api/v1/settings")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(settings)
        return try await Self.send(request, session: session)
    }

    /// Installs `id` from `repository`, or updates it when it's installed.
    func install(_ id: String, from repository: Int64) async throws(ChekError) -> ChekAPI.InstalledExtension {
        var request = authorized("api/v1/me/extensions/\(id)")
        request.httpMethod = "PUT"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["repositoryId": repository])
        return try await Self.send(request, session: session)
    }

    func uninstall(_ id: String) async throws(ChekError) {
        var request = authorized("api/v1/me/extensions/\(id)")
        request.httpMethod = "DELETE"
        try await Self.sendWithoutBody(request, session: session)
    }

    /// One page of a source's series matching `query`, or the ones it
    /// shows first when `query` is empty. Pages count from 1.
    func search(source: String, query: String, page: Int) async throws(ChekError) -> ChekAPI.SourceSearchPage {
        var items = [URLQueryItem(name: "page", value: String(page))]
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: String(query.prefix(200))))
        }
        // A source fetches from its site while you wait, which can be slow.
        var request = authorized("api/v1/me/extensions/\(source)/search", query: items)
        request.timeoutInterval = 60
        return try await Self.send(request, session: session)
    }

    func series(_ series: String, inSource source: String) async throws(ChekError) -> ChekAPI.SourceSeries {
        var request = authorized("api/v1/me/extensions/\(source)/series", query: [URLQueryItem(name: "seriesId", value: series)])
        request.timeoutInterval = 60
        return try await Self.send(request, session: session)
    }

    /// Which end of a series a page of chapters counts from.
    enum ChapterOrder: String, Sendable {
        case oldestFirst = "asc"
        case newestFirst = "desc"
    }

    /// One page of a series' chapters: `limit` of them from `offset`, or
    /// from just past chapter `after`, counted from the end `order` names.
    /// The server reads the whole list from the source once and keeps it,
    /// so later pages, in either order, cost the source nothing; `refresh`
    /// asks it to read the list again.
    func chapterPage(ofSeries series: String, inSource source: String, order: ChapterOrder, offset: Int = 0, after: String? = nil, limit: Int, refresh: Bool = false) async throws(ChekError) -> ChekAPI.SourceChapterPage {
        var query = [
            URLQueryItem(name: "seriesId", value: series),
            URLQueryItem(name: "order", value: order.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let after {
            query.append(URLQueryItem(name: "after", value: after))
        } else {
            query.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "true"))
        }
        var request = authorized("api/v1/me/extensions/\(source)/chapters", query: query)
        // The first page reads the whole list from the source's site.
        request.timeoutInterval = 120
        // Asked for anew, a refresh mustn't be answered from the cache.
        if refresh {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        return try await Self.send(request, session: session)
    }

    /// The content ratings your search on this server is limited to.
    func contentRatings() async throws(ChekError) -> [ChekAPI.ContentRating] {
        let answer: ChekAPI.ContentRatings = try await Self.send(authorized("api/v1/me/content-ratings"), session: session)
        return answer.contentRatings.compactMap(ChekAPI.ContentRating.init(rawValue:))
    }

    /// Replaces the content ratings your search on this server is limited
    /// to, giving back the ones it now uses.
    func setContentRatings(_ ratings: Set<ChekAPI.ContentRating>) async throws(ChekError) -> [ChekAPI.ContentRating] {
        var request = authorized("api/v1/me/content-ratings")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(ChekAPI.ContentRatings(contentRatings: ratings.sorted().map(\.rawValue)))
        let answer: ChekAPI.ContentRatings = try await Self.send(request, session: session)
        return answer.contentRatings.compactMap(ChekAPI.ContentRating.init(rawValue:))
    }

    /// Makes `group`'s release of each chapter in a series the one picked,
    /// for you on every device, or goes back to the default for nil.
    func setReleaseGroup(_ group: String?, forSeries series: String, inSource source: String) async throws(ChekError) {
        var request = authorized("api/v1/me/extensions/\(source)/release-group")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            var seriesId: String
            var releaseGroup: String?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(seriesId, forKey: .seriesId)
                // Sent as null to clear, rather than left out.
                try container.encode(releaseGroup, forKey: .releaseGroup)
            }

            enum CodingKeys: String, CodingKey { case seriesId, releaseGroup }
        }
        request.httpBody = try? JSONEncoder().encode(Body(seriesId: series, releaseGroup: group))
        try await Self.sendWithoutBody(request, session: session)
    }

    /// Every chapter from position `start` up to `end` in reading order,
    /// a server page at a time. Only for something you asked of the whole
    /// series, such as downloading every unread chapter.
    func chapters(ofSeries series: String, inSource source: String, from start: Int = 0, to end: Int? = nil) async throws(ChekError) -> [ChekAPI.SourceChapter] {
        var chapters: [ChekAPI.SourceChapter] = []
        var offset = start
        while true {
            let wanted = end.map { min(500, $0 - offset) } ?? 500
            guard wanted > 0 else { break }
            let page = try await chapterPage(ofSeries: series, inSource: source, order: .oldestFirst, offset: offset, limit: wanted)
            chapters += page.items
            // Offsets count releases, which a chapter can have several of.
            guard let next = page.nextOffset, next > offset, !page.items.isEmpty else { break }
            offset = next
            if let end, offset >= end { break }
        }
        return chapters
    }

    func pages(ofChapter chapter: String, inSource source: String) async throws(ChekError) -> [ChekAPI.SourcePage] {
        var request = authorized("api/v1/me/extensions/\(source)/pages", query: [URLQueryItem(name: "chapterId", value: chapter)])
        request.timeoutInterval = 60
        let page: ChekAPI.Items<ChekAPI.SourcePage> = try await Self.send(request, session: session)
        return page.items.sorted { $0.index < $1.index }
    }

    /// How to read a chapter: its pages, or the file it is.
    func chapterContent(_ chapter: String, inSource source: String) async throws(ChekError) -> ChekAPI.ChapterContent {
        var request = authorized("api/v1/me/extensions/\(source)/content", query: [URLQueryItem(name: "chapterId", value: chapter)])
        request.timeoutInterval = 60
        var content: ChekAPI.ChapterContent = try await Self.send(request, session: session)
        content.pages?.sort { $0.index < $1.index }
        return content
    }

    /// A request for an image a source route returned, which is a path on
    /// this server rather than on the source's site.
    ///
    /// The path comes from an extension, so it's only followed when it
    /// stays on this server; anything else would carry the session token
    /// to whatever host the extension named.
    func imageRequest(_ path: String) -> URLRequest? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host()?.lowercased() == baseURL.host()?.lowercased(),
              url.port == baseURL.port
        else { return nil }
        return authorize(URLRequest(url: url, timeoutInterval: 60))
    }

    // MARK: - Reading

    func pageCount(of publication: Int64) async throws(ChekError) -> Int {
        let pages: ChekAPI.Items<ChekAPI.PageInfo> = try await get("api/v1/publications/\(publication)/pages")
        return pages.items.count
    }

    /// The saved position. It's asked for while a publication opens, so it
    /// gives up quickly rather than holding the reader back.
    func progress(of publication: Int64) async throws(ChekError) -> ChekAPI.Progress {
        var request = authorized("api/v1/publications/\(publication)/progress")
        request.timeoutInterval = 5
        return try await Self.send(request, session: session)
    }

    /// Saves a position if the server's is still at `expectedRevision`,
    /// and throws ``ChekError/progressConflict(_:)`` with the newer one if not.
    func saveProgress(_ locator: Locator, of publication: Int64, expectedRevision: Int64) async throws(ChekError) -> ChekAPI.Progress {
        struct Body: Encodable {
            var expectedRevision: Int64
            var locator: Locator
        }
        var request = authorized("api/v1/publications/\(publication)/progress")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(expectedRevision: expectedRevision, locator: locator))
        return try await Self.send(request, session: session)
    }

    func coverRequest(of publication: Int64) -> URLRequest {
        authorized("api/v1/publications/\(publication)/cover")
    }

    func fileRequest(of publication: Int64) -> URLRequest {
        authorized("api/v1/publications/\(publication)/file")
    }

    func pageRequest(_ index: Int, of publication: Int64) -> URLRequest {
        authorized("api/v1/publications/\(publication)/pages/\(index)")
    }

    /// The file's address, for streaming with range requests. Credentials
    /// go on each request through ``authorize(_:)``.
    func fileURL(of publication: Int64) -> URL {
        baseURL.appending(path: "api/v1/publications/\(publication)/file")
    }

    func authorize(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Requests

    private func authorized(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        return authorize(URLRequest(url: url, timeoutInterval: 30))
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = [], cursor: String?, limit: Int = 60) async throws(ChekError) -> Value {
        var query = query
        query.append(URLQueryItem(name: "limit", value: String(limit)))
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await Self.send(authorized(path, query: query), session: session)
    }

    private func get<Value: Decodable>(_ path: String) async throws(ChekError) -> Value {
        try await Self.send(authorized(path), session: session)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }()

    /// Sends a request whose success has no body, such as a delete.
    private static func sendWithoutBody(_ request: URLRequest, session: URLSession) async throws(ChekError) {
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw .offline(error)
        } catch {
            throw .invalidResponse
        }
        guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw .unauthorized
        case 404: throw .notFound
        default: throw .server(status: http.statusCode, code: nil)
        }
    }

    private static func send<Value: Decodable>(_ request: URLRequest, session: URLSession) async throws(ChekError) -> Value {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw .offline(error)
        } catch {
            throw .invalidResponse
        }
        guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(Value.self, from: data)
            } catch {
                throw .invalidResponse
            }
        case 401:
            throw .unauthorized
        case 404:
            throw .notFound
        case 409:
            if let conflict = try? decoder.decode(ChekAPI.ProgressConflict.self, from: data) {
                throw .progressConflict(conflict.current)
            }
            fallthrough
        default:
            throw .server(status: http.statusCode, code: (try? decoder.decode(ChekAPI.ErrorBody.self, from: data))?.code)
        }
    }
}

/// Streams a comic's pages from the server one at a time, so the first
/// page shows without fetching the rest.
nonisolated struct ChekPageSource: PageSource {
    let server: ServerAccess
    let publication: Int64
    let knownPageCount: Int?

    private var folder: PageFolder { PublicationFiles.folder(for: publication, on: server.account) }

    func pageCount() async throws -> Int {
        // A downloaded comic reads from the device, offline or not.
        if let count = folder.downloadedPageCount {
            return count
        }
        if let knownPageCount, knownPageCount > 0 {
            return knownPageCount
        }
        let publication = publication
        return try await server.request { client throws(ChekError) in try await client.pageCount(of: publication) }
    }

    func page(at index: Int) async throws -> Data {
        if folder.isComplete {
            return try Data(contentsOf: folder.page(index))
        }
        let client = try await server.client()
        return try await server.data(for: client.pageRequest(index, of: publication))
    }
}
