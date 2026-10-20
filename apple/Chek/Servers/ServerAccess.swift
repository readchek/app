import Foundation

/// How something that reads from a server for a while, such as a page
/// source, reaches it: the client that's signed in now, found each time so
/// a sign-in during reading is used at once, and a word to the store when
/// the server ends the session, so the rest of the app shows it too.
nonisolated struct ServerAccess: Sendable {
    let account: UUID
    private let store: ServerStore

    init(account: UUID, store: ServerStore) {
        self.account = account
        self.store = store
    }

    /// The signed-in client, or `unauthorized` while there's none.
    func client() async throws(ChekError) -> ChekClient {
        guard let client = await store.client(for: account) else { throw .unauthorized }
        return client
    }

    /// Runs `operation` against the server, as ``ServerStore/request(_:_:)``
    /// does, from off the main actor.
    func request<Value: Sendable>(_ operation: @Sendable (ChekClient) async throws(ChekError) -> Value) async throws(ChekError) -> Value {
        let client = try await client()
        do {
            return try await operation(client)
        } catch .unauthorized {
            await store.sessionEnded(account)
            throw .unauthorized
        }
    }

    /// Fetches `request`, which was made by ``client()`` against the server,
    /// and gives back its body.
    func data(for request: URLRequest) async throws(ChekError) -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw .offline(error)
        } catch {
            throw .invalidResponse
        }
        guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
        switch http.statusCode {
        case 200:
            return data
        case 401:
            await store.sessionEnded(account)
            throw .unauthorized
        default:
            throw .server(status: http.statusCode, code: nil)
        }
    }
}
