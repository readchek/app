import Foundation
import Observation

/// Search results from every signed-in server and the sites added to them,
/// or from the one place the search is narrowed to.
@MainActor
@Observable
final class ServerSearchModel {
    struct Results: Identifiable {
        let account: UUID
        let name: String
        var state: LoadState<[RemotePublication]>
        /// Where the next page starts, when there's more.
        var nextCursor: String?
        /// When its first results came, counted across every place, so
        /// sections show in the order they answered.
        var arrival: Int?

        var id: UUID { account }
    }

    /// Series found by one of a server's sources, such as MangaDex.
    struct SourceResults: Identifiable {
        let account: UUID
        let source: ChekAPI.InstalledExtension
        let serverName: String
        var state: LoadState<[ChekAPI.SourceSeriesItem]>
        /// The page to ask for next, when the site has more.
        var nextPage: Int?
        var arrival: Int?

        var id: String { "\(account.uuidString)/\(source.id)" }
    }

    /// A place that found something, as one section of the results.
    enum Found: Identifiable {
        case server(Results)
        case source(SourceResults)

        var id: String {
            switch self {
            case .server(let results): results.account.uuidString
            case .source(let results): results.id
            }
        }

        var arrival: Int {
            switch self {
            case .server(let results): results.arrival ?? .max
            case .source(let results): results.arrival ?? .max
            }
        }
    }

    private(set) var results: [Results] = []
    private(set) var sourceResults: [SourceResults] = []
    /// Each signed-in server's usable sites, for searching and for choosing
    /// one to search.
    private(set) var sites: [UUID: [ChekAPI.InstalledExtension]] = [:]
    /// Whether a further page is being read for a narrowed search.
    private(set) var isLoadingMore = false
    /// What the results are for.
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var filters = SearchFilters()
    /// The content ratings the results were found under.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var arrivals = 0
    /// When each server's sites were last asked for. Asked again after a
    /// while, so a site added since shows up without a relaunch.
    @ObservationIgnored private var sitesFetched: [UUID: Date] = [:]

    /// The places that found something, in the order they answered.
    var found: [Found] {
        let servers = results.filter { $0.arrival != nil }.map(Found.server)
        let sources = sourceResults.filter { $0.arrival != nil }.map(Found.source)
        return (servers + sources).sorted { $0.arrival < $1.arrival }
    }

    /// The places whose search failed.
    var failures: [Found] {
        results.filter(\.state.isFailed).map(Found.server) + sourceResults.filter(\.state.isFailed).map(Found.source)
    }

    /// The places still looking, by name.
    var searching: [String] {
        results.filter { $0.state.isLoading }.map(\.name) + sourceResults.filter { $0.state.isLoading }.map(\.source.name)
    }

    /// Asks each signed-in server which sites it has, unless it was asked
    /// lately. A server that doesn't answer keeps what it said last time.
    func loadSites(servers: ServerStore) async {
        for account in servers.accounts() where servers.state(of: account.id) == .signedIn {
            let id = account.id
            if let fetched = sitesFetched[id], Date.now.timeIntervalSince(fetched) < 120 { continue }
            let items = (try? await servers.request(id) { client throws(ChekError) in
                try await client.installedExtensionsIfSupported()
            }).flatMap(\.self)
            if let items {
                sites[id] = items.filter(\.usable)
                sitesFetched[id] = .now
            } else if sites[id] == nil {
                sites[id] = []
            }
        }
    }

    /// How much longer typing has to rest before sites are asked, on top of
    /// the pause that searches libraries. A site answers each search with
    /// requests to the site itself, which its bot checks count, so it
    /// shouldn't be asked for every word on the way to the one meant.
    static let siteDelay: Duration = .milliseconds(700)

    func search(_ text: String, filters: SearchFilters, servers: ServerStore) async {
        generation += 1
        let current = generation
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // The same search again, as when coming back to the tab, keeps
        // what each place found and asks only the ones that hadn't
        // answered, so nothing found disappears and comes back.
        let isRepeat = query == self.query && filters == self.filters && servers.contentRatingsRevision == revision
        self.query = query
        self.filters = filters
        revision = servers.contentRatingsRevision
        guard !query.isEmpty else {
            results = []
            sourceResults = []
            return
        }
        if !isRepeat {
            arrivals = 0
        }
        let signedIn = servers.accounts().filter { servers.state(of: $0.id) == .signedIn }
        let accounts: [ServerAccount] = switch filters.scope {
        case .everywhere: signedIn
        case .server(let id): signedIn.filter { $0.id == id }
        case .library, .source: []
        }
        let kept = isRepeat ? Dictionary(results.filter { !$0.state.isLoading }.map { ($0.account, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        let keptSources = isRepeat ? Dictionary(sourceResults.filter { !$0.state.isLoading }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        results = accounts.map { kept[$0.id] ?? Results(account: $0.id, name: $0.name, state: .loading) }
        if !isRepeat {
            sourceResults = []
        }
        switch filters.scope {
        case .everywhere, .source: await loadSites(servers: servers)
        case .library, .server: break
        }
        guard current == generation else { return }
        sourceResults = signedIn.flatMap { account in
            (sites[account.id] ?? []).filter { site in
                switch filters.scope {
                case .everywhere: SearchFilters.source(site, matches: filters.kind)
                case .source(let server, let id): server == account.id && site.id == id
                case .library, .server: false
                }
            }
            .map {
                // A site that can't have the kind asked for has nothing,
                // without asking it.
                let state: LoadState<[ChekAPI.SourceSeriesItem]> = SearchFilters.source($0, matches: filters.kind) ? .loading : .loaded([])
                let fresh = SourceResults(account: account.id, source: $0, serverName: account.name, state: state)
                return keptSources[fresh.id] ?? fresh
            }
        }
        // Each place answers on its own, so a slow site doesn't hold up
        // the rest, and its section comes when it has something.
        let sourceTasks = sourceResults.filter(\.state.isLoading).map { target in
            Task {
                // A new keystroke cancels this wait, so the site is never asked.
                try? await Task.sleep(for: Self.siteDelay)
                guard !Task.isCancelled,
                      let answer = await Self.searchSource(target.source.id, query: query, page: 1, account: target.account, servers: servers),
                      current == generation else { return }
                settle(source: target.id, answer)
            }
        }
        let tasks = results.filter(\.state.isLoading).map { target in
            Task {
                guard let answer = await Self.searchServer(target.account, query: query, cursor: nil, servers: servers),
                      current == generation else { return }
                settle(server: target.account, answer)
            }
        }
        await withTaskCancellationHandler {
            for task in tasks {
                await task.value
            }
            for task in sourceTasks {
                await task.value
            }
        } onCancel: {
            for task in tasks {
                task.cancel()
            }
            for task in sourceTasks {
                task.cancel()
            }
        }
    }

    /// Searches one shared library again, after it failed.
    func retry(server account: UUID, servers: ServerStore) async {
        guard let index = results.firstIndex(where: { $0.account == account }) else { return }
        let current = generation
        results[index].state = .loading
        guard let answer = await Self.searchServer(account, query: query, cursor: nil, servers: servers), current == generation else { return }
        settle(server: account, answer)
    }

    /// Searches one site again, after it failed.
    func retry(source id: String, servers: ServerStore) async {
        guard let index = sourceResults.firstIndex(where: { $0.id == id }) else { return }
        let current = generation
        let target = sourceResults[index]
        sourceResults[index].state = .loading
        guard let answer = await Self.searchSource(target.source.id, query: query, page: 1, account: target.account, servers: servers), current == generation else { return }
        settle(source: id, answer)
    }

    /// Adds the next page of a shared library's results, as its last ones
    /// come into view in a narrowed search.
    func loadMore(server account: UUID, servers: ServerStore) async {
        guard !isLoadingMore, let index = results.firstIndex(where: { $0.account == account }),
              let cursor = results[index].nextCursor, case .loaded(let items) = results[index].state else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let (state, next) = await Self.searchServer(account, query: query, cursor: cursor, servers: servers),
              current == generation, case .loaded(let more) = state,
              let index = results.firstIndex(where: { $0.account == account }) else { return }
        let seen = Set(items.map(\.id))
        results[index].state = .loaded(items + matching(more).filter { !seen.contains($0.id) })
        results[index].nextCursor = next
    }

    /// Adds the next page of a site's results.
    func loadMore(source id: String, servers: ServerStore) async {
        guard !isLoadingMore, let index = sourceResults.firstIndex(where: { $0.id == id }),
              let page = sourceResults[index].nextPage, case .loaded(let items) = sourceResults[index].state else { return }
        let current = generation
        let target = sourceResults[index]
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let (state, hasMore) = await Self.searchSource(target.source.id, query: query, page: page, account: target.account, servers: servers),
              current == generation, case .loaded(let more) = state,
              let index = sourceResults.firstIndex(where: { $0.id == id }) else { return }
        let seen = Set(items.map(\.id))
        sourceResults[index].state = .loaded(items + more.filter { !seen.contains($0.id) })
        sourceResults[index].nextPage = hasMore ? page + 1 : nil
    }

    private func settle(server account: UUID, _ answer: (LoadState<[RemotePublication]>, String?)) {
        guard let index = results.firstIndex(where: { $0.account == account }) else { return }
        var (state, next) = answer
        if case .loaded(let items) = state {
            state = .loaded(matching(items))
        }
        results[index].state = state
        results[index].nextCursor = next
        if results[index].arrival == nil, state.value?.isEmpty == false {
            results[index].arrival = nextArrival()
        }
    }

    private func settle(source id: String, _ answer: (LoadState<[ChekAPI.SourceSeriesItem]>, Bool)) {
        guard let index = sourceResults.firstIndex(where: { $0.id == id }) else { return }
        let (state, hasMore) = answer
        sourceResults[index].state = state
        sourceResults[index].nextPage = hasMore ? 2 : nil
        if sourceResults[index].arrival == nil, state.value?.isEmpty == false {
            sourceResults[index].arrival = nextArrival()
        }
    }

    /// A library's results of the kind asked for, since its search finds
    /// both.
    private func matching(_ items: [RemotePublication]) -> [RemotePublication] {
        guard let kind = filters.kind else { return items }
        return items.filter { $0.kind == kind }
    }

    private func nextArrival() -> Int {
        arrivals += 1
        return arrivals
    }

    /// One library's results and where its next page starts, or nil when
    /// the search was given up because a newer one replaced it, which isn't
    /// a failure to show.
    static func searchServer(_ id: UUID, query: String, cursor: String?, servers: ServerStore) async -> (LoadState<[RemotePublication]>, String?)? {
        do {
            let page = try await servers.request(id) { client throws(ChekError) in
                try await client.search(query, cursor: cursor)
            }
            return (.loaded(page.items.map { RemotePublication($0, server: id) }), page.nextCursor)
        } catch {
            return Task.isCancelled || error.isCancellation ? nil : (.failed(DisplayError(error)), nil)
        }
    }

    /// One site's results and whether it has more, or nil when the search
    /// was given up.
    static func searchSource(_ source: String, query: String, page: Int, account: UUID, servers: ServerStore) async -> (LoadState<[ChekAPI.SourceSeriesItem]>, Bool)? {
        do {
            let result = try await servers.request(account) { client throws(ChekError) in
                try await client.search(source: source, query: query, page: page)
            }
            return (.loaded(result.items), result.hasMore)
        } catch {
            return Task.isCancelled || error.isCancellation ? nil : (.failed(DisplayError(error)), false)
        }
    }
}

extension LoadState {
    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

extension ChekError {
    /// A request stopped because nobody wants its answer any more, as when
    /// typing on replaces a search.
    var isCancellation: Bool {
        if case .offline(let error) = self { error.code == .cancelled } else { false }
    }
}
