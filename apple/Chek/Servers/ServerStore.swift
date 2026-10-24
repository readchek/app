import ChekReader
import Foundation
import Observation
import SwiftData
import UIKit

/// Owns the servers you've connected: adding and removing them, signing in
/// and out, and the client each one is read through.
///
/// Every request to a server goes through ``request(_:_:)``, so a session
/// that ends anywhere in the app marks its account as signed out in one place.
@MainActor
@Observable
final class ServerStore {
    enum ConnectionState: Equatable {
        case signedIn
        case signedOut
    }

    /// Accounts whose session ended. Every other account is signed in.
    private(set) var signedOut: Set<UUID> = []
    /// Told when a server is removed, so what else was kept for it goes too.
    @ObservationIgnored var onRemove: ((UUID) -> Void)?

    private let context: ModelContext
    private let keychain: Keychain
    /// Clients by account, made once per token so views can compare them.
    @ObservationIgnored private var clients: [UUID: ChekClient] = [:]

    init(context: ModelContext, keychain: Keychain = .serverTokens) {
        self.context = context
        self.keychain = keychain
        forgetDemo()
        for account in accounts() where keychain.token(for: account.id) == nil {
            signedOut.insert(account.id)
        }
        removeOrphanedReadingStates()
    }

    // MARK: - Demo

    /// Whether the demo server is connected. Stored, so views showing the
    /// banner redraw when it starts and ends.
    private(set) var isDemo = false

    /// Connects the demo server, as a temporary account.
    func startDemo() async throws(DisplayError) {
        if isDemo { return }
        let session = try await signIn(at: DemoMode.baseURL, name: DemoMode.user, password: DemoMode.password)
        let account = ServerAccount(
            id: DemoMode.accountID,
            kind: .chek,
            name: DemoMode.name,
            baseURL: DemoMode.baseURL,
            userName: session.user.name,
            userID: session.user.id,
            sortIndex: (accounts().map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(account)
        try? context.save()
        keep(session, for: account)
        isDemo = true
    }

    /// Ends the demo, forgetting the account and everything kept for it.
    func endDemo() async {
        guard let account = account(DemoMode.accountID) else { return }
        await remove(account)
    }

    /// The demo doesn't survive a relaunch: whatever a previous run left
    /// of it goes before the accounts are read.
    private func forgetDemo() {
        guard let account = account(DemoMode.accountID) else { return }
        let id = account.id
        keychain.removeToken(for: id)
        for state in (try? context.fetch(FetchDescriptor<RemoteReadingState>(predicate: #Predicate { $0.serverID == id }))) ?? [] {
            context.delete(state)
        }
        for state in (try? context.fetch(FetchDescriptor<SourceReadingState>(predicate: #Predicate { $0.serverID == id }))) ?? [] {
            context.delete(state)
        }
        for follow in (try? context.fetch(FetchDescriptor<FollowedSeries>(predicate: #Predicate { $0.serverID == id }))) ?? [] {
            context.delete(follow)
        }
        context.delete(account)
        try? context.save()
        try? FileManager.default.removeItem(at: ServerFiles.folder(for: id))
        // Downloads and kept listings go when their stores start, which
        // drop whatever belongs to a server that's no longer here.
    }

    /// Places kept for servers that are no longer connected. Older builds
    /// removed servers with a batch delete that could leave these behind.
    private func removeOrphanedReadingStates() {
        let servers = Set(accounts().map(\.id))
        let states = (try? context.fetch(FetchDescriptor<RemoteReadingState>())) ?? []
        let orphans = states.filter { !servers.contains($0.serverID) }
        let sourceStates = (try? context.fetch(FetchDescriptor<SourceReadingState>())) ?? []
        let sourceOrphans = sourceStates.filter { !servers.contains($0.serverID) }
        guard !orphans.isEmpty || !sourceOrphans.isEmpty else { return }
        for state in orphans {
            context.delete(state)
        }
        for state in sourceOrphans {
            context.delete(state)
        }
        try? context.save()
    }

    func state(of account: UUID) -> ConnectionState {
        signedOut.contains(account) ? .signedOut : .signedIn
    }

    func accounts() -> [ServerAccount] {
        (try? context.fetch(FetchDescriptor<ServerAccount>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    func account(_ id: UUID) -> ServerAccount? {
        var descriptor = FetchDescriptor<ServerAccount>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The client for `account`, or nil while it's signed out.
    func client(for account: UUID) -> ChekClient? {
        if let client = clients[account] {
            return client
        }
        guard !signedOut.contains(account),
              let server = self.account(account),
              let token = keychain.token(for: account)
        else { return nil }
        let client = ChekClient(baseURL: server.baseURL, token: token)
        clients[account] = client
        return client
    }

    /// Runs `operation` against `account`'s server, marking the account
    /// signed out if the server says its session ended.
    func request<Value>(_ account: UUID, _ operation: (ChekClient) async throws(ChekError) -> Value) async throws(ChekError) -> Value {
        guard let client = client(for: account) else { throw .unauthorized }
        do {
            return try await operation(client)
        } catch .unauthorized {
            sessionEnded(account)
            throw .unauthorized
        }
    }

    /// The cover of `publication`: the one saved with its download, else
    /// fetched with `account`'s credentials. Signed out, the request can
    /// only fail, but the copy on disk from last time still shows.
    func cover(of publication: Int64, on account: UUID) -> CoverSource {
        let saved = PublicationFiles.cover(of: publication, on: account)
        if FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)) {
            return .file(saved)
        }
        guard let client = client(for: account) ?? self.account(account).map({ ChekClient(baseURL: $0.baseURL, token: "") }) else {
            return .none
        }
        return .remote(key: "server/\(account.uuidString)/\(publication)/cover", request: client.coverRequest(of: publication))
    }

    // MARK: - Connecting

    /// Signs in to the Chek server at `address` and remembers it.
    /// `displayName` is what the server is called in Chek; when empty it
    /// starts as the server's host name.
    func connect(address: String, displayName: String = "", name: String, password: String) async throws(DisplayError) -> ServerAccount {
        guard let baseURL = Self.baseURL(from: address) else {
            throw DisplayError(title: String(localized: "That doesn't look like an address."), message: String(localized: "Enter the address you were given, such as books.example.com."))
        }
        if let existing = accounts().first(where: { $0.baseURL == baseURL && $0.userName.caseInsensitiveCompare(name) == .orderedSame }) {
            try await signIn(existing, password: password)
            return existing
        }
        let session = try await signIn(at: baseURL, name: name, password: password)
        let account = ServerAccount(
            kind: .chek,
            name: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? baseURL.host() ?? baseURL.absoluteString
                : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL,
            userName: session.user.name,
            userID: session.user.id,
            sortIndex: (accounts().map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(account)
        try? context.save()
        keep(session, for: account)
        return account
    }

    /// Signs `account` in again after its session ended.
    func signIn(_ account: ServerAccount, password: String) async throws(DisplayError) {
        let session = try await signIn(at: account.baseURL, name: account.userName, password: password)
        keep(session, for: account)
    }

    /// Stores a new session's token, and makes its client straight away so
    /// the session works even if the Keychain refuses the token, as it does
    /// in builds without signing.
    private func keep(_ session: ChekAPI.Session, for account: ServerAccount) {
        keychain.setToken(session.token, for: account.id)
        clients[account.id] = ChekClient(baseURL: account.baseURL, token: session.token)
        signedOut.remove(account.id)
    }

    func signOut(_ account: ServerAccount) async {
        let client = client(for: account.id)
        sessionEnded(account.id)
        await client?.signOut()
    }

    /// Forgets the server, your places in it and anything downloaded from it.
    func remove(_ account: ServerAccount) async {
        let id = account.id
        // Gone from the device first, so it leaves the list at once; ending
        // the session on the server can wait for the network.
        let client = client(for: id)
        sessionEnded(id)
        // One by one: a batch delete doesn't reach `@Query`, so the
        // now-reading bar would keep showing a book from a server that's gone.
        let states = (try? context.fetch(FetchDescriptor<RemoteReadingState>(predicate: #Predicate { $0.serverID == id }))) ?? []
        for state in states {
            context.delete(state)
        }
        let sourceStates = (try? context.fetch(FetchDescriptor<SourceReadingState>(predicate: #Predicate { $0.serverID == id }))) ?? []
        for state in sourceStates {
            context.delete(state)
        }
        for follow in (try? context.fetch(FetchDescriptor<FollowedSeries>(predicate: #Predicate { $0.serverID == id }))) ?? [] {
            context.delete(follow)
        }
        context.delete(account)
        try? context.save()
        signedOut.remove(id)
        if id == DemoMode.accountID {
            isDemo = false
        }
        try? FileManager.default.removeItem(at: ServerFiles.folder(for: id))
        onRemove?(id)
        await client?.signOut()
    }

    /// Saves the order you arranged servers in.
    func reorder(_ accounts: [ServerAccount]) {
        for (index, account) in accounts.enumerated() where account.sortIndex != index {
            account.sortIndex = index
        }
        try? context.save()
    }

    func rename(_ account: ServerAccount, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A removed account has no context, and changing it would crash.
        guard !trimmed.isEmpty, trimmed != account.name, account.modelContext != nil else { return }
        account.name = trimmed
        try? context.save()
    }

    /// The server said `account`'s session ended, so its token is dropped
    /// and screens show it signed out until it signs in again.
    func sessionEnded(_ account: UUID) {
        keychain.removeToken(for: account)
        clients[account] = nil
        signedOut.insert(account)
    }

    private func signIn(at baseURL: URL, name: String, password: String) async throws(DisplayError) -> ChekAPI.Session {
        do {
            try await ChekClient.checkHealth(at: baseURL)
        } catch {
            throw DisplayError(title: String(localized: "Couldn't find a library at that address."), message: String(localized: "Check the address with whoever shared it, and that you're online."))
        }
        do {
            return try await ChekClient.signIn(at: baseURL, name: name, password: password, device: UIDevice.current.name)
        } catch .unauthorized {
            throw DisplayError(title: String(localized: "The name or password is wrong."))
        } catch .server(status: 429, _) {
            throw DisplayError(title: String(localized: "Too many tries."), message: String(localized: "Wait a minute and try again."))
        } catch {
            throw DisplayError(error)
        }
    }

    /// The server's base address from what someone typed: a scheme is added
    /// when it's missing, and paths, queries and trailing slashes go.
    static func baseURL(from address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            // HTTPS unless the host is on this machine or the local
            // network, where servers usually run without TLS.
            let host = URLComponents(string: "https://" + text)?.host ?? ""
            text = (isLocalNetwork(host) ? "http://" : "https://") + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

/// Whether `host` is this machine or a private network address, judged
/// from the whole host rather than its prefix, so `localhost.example.com`
/// doesn't count.
nonisolated func isLocalNetwork(_ host: String) -> Bool {
    let host = host.lowercased()
    if host == "localhost" || host == "::1" || host.hasSuffix(".local") {
        return true
    }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
    guard parts.count == 4, host.split(separator: ".").count == 4 else { return false }
    switch (parts[0], parts[1]) {
    case (127, _), (10, _), (192, 168): return true
    case (172, 16...31): return true
    default: return false
    }
}

/// Where files downloaded from servers are kept: a folder per account in
/// Caches, since they can always be fetched again.
nonisolated enum ServerFiles {
    static func folder(for account: UUID) -> URL {
        URL.cachesDirectory.appending(path: "Servers/\(account.uuidString)", directoryHint: .isDirectory)
    }

    static func file(for publication: Int64, format: String, account: UUID) -> URL {
        // The format comes from the server, so only letters and digits
        // reach the file name; anything else could step out of the folder.
        let safeFormat = String(format.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8))
        return folder(for: account).appending(path: "\(publication).\(safeFormat.isEmpty ? "bin" : safeFormat)")
    }
}
