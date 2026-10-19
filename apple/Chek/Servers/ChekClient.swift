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

    func search(_ text: String, cursor: String?) async throws(ChekError) -> ChekAPI.Page<ChekAPI.PublicationSummary> {
        try await get("api/v1/search", query: [URLQueryItem(name: "q", value: String(text.prefix(200)))], cursor: cursor)
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
    let client: ChekClient
    let publication: Int64
    let knownPageCount: Int?

    func pageCount() async throws -> Int {
        if let knownPageCount, knownPageCount > 0 {
            return knownPageCount
        }
        return try await client.pageCount(of: publication)
    }

    func page(at index: Int) async throws -> Data {
        let (data, response) = try await client.session.data(for: client.pageRequest(index, of: publication))
        guard let http = response as? HTTPURLResponse else { throw ChekError.invalidResponse }
        switch http.statusCode {
        case 200: return data
        case 401: throw ChekError.unauthorized
        default: throw ChekError.server(status: http.statusCode, code: nil)
        }
    }
}
