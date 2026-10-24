import SwiftData
import SwiftUI

/// Looks through everything at once.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ServerStore.self) private var servers
    @State private var text = ""
    @State private var serverResults = ServerSearchModel()

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.searchPath) {
            SearchResults(text: text, serverResults: serverResults)
                .demoBanner()
                .navigationTitle("Search")
                .routeDestinations()
        }
        .searchable(text: $text, prompt: Text("Books, Comics and Authors"))
        .task(id: text) {
            // Waiting for a pause in typing keeps servers from getting a
            // request per keystroke. A new keystroke cancels the wait.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await serverResults.search(text, servers: servers)
        }
    }
}

/// Search results from every signed-in server.
@MainActor
@Observable
final class ServerSearchModel {
    struct Results: Identifiable {
        let account: UUID
        let name: String
        var state: LoadState<[RemotePublication]>

        var id: UUID { account }
    }

    /// Series found by one of a server's sources, such as MangaDex.
    struct SourceResults: Identifiable {
        let account: UUID
        let source: ChekAPI.InstalledExtension
        let serverName: String
        var state: LoadState<[ChekAPI.SourceSeriesItem]>

        var id: String { "\(account.uuidString)/\(source.id)" }
    }

    private(set) var results: [Results] = []
    private(set) var sourceResults: [SourceResults] = []
    @ObservationIgnored private var generation = 0
    /// Each server's installed sources, asked for once rather than with
    /// every search.
    /// Each server's installed sources, with when they were asked for.
    /// Asked again after a while, so a source installed since shows up
    /// in search without a relaunch.
    @ObservationIgnored private var sources: [UUID: (at: Date, items: [ChekAPI.InstalledExtension])] = [:]

    func search(_ text: String, servers: ServerStore) async {
        generation += 1
        let current = generation
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let accounts = servers.accounts().filter { servers.state(of: $0.id) == .signedIn }
        guard !query.isEmpty else {
            results = []
            sourceResults = []
            return
        }
        results = accounts.map { Results(account: $0.id, name: $0.name, state: .loading) }
        for account in accounts where sources[account.id].map({ Date.now.timeIntervalSince($0.at) > 120 }) ?? true {
            let id = account.id
            let items = (try? await servers.request(id) { client throws(ChekError) in
                try await client.installedExtensionsIfSupported()
            }).flatMap(\.self)
            // A server that didn't answer keeps what it said last time.
            if let items {
                sources[id] = (.now, items)
            } else if sources[id] == nil {
                sources[id] = (.distantPast, [])
            }
        }
        guard current == generation else { return }
        sourceResults = accounts.flatMap { account in
            (sources[account.id]?.items ?? []).filter(\.usable).map {
                SourceResults(account: account.id, source: $0, serverName: account.name, state: .loading)
            }
        }
        // Sources look on their sites while you wait, so each answers on
        // its own like the servers do.
        let sourceTasks = sourceResults.map { results in
            let id = results.id
            let account = results.account
            let source = results.source.id
            return Task {
                let state: LoadState<[ChekAPI.SourceSeriesItem]>
                do {
                    let page = try await servers.request(account) { client throws(ChekError) in
                        try await client.search(source: source, query: query, page: 1)
                    }
                    state = .loaded(page.items)
                } catch {
                    state = .failed(DisplayError(error))
                }
                guard current == generation, let index = sourceResults.firstIndex(where: { $0.id == id }) else { return }
                sourceResults[index].state = state
            }
        }
        // Each server answers on its own, so a slow one doesn't hold up the rest.
        let tasks = accounts.map { account in
            let id = account.id
            return Task {
                let state: LoadState<[RemotePublication]>
                do {
                    let page = try await servers.request(id) { client throws(ChekError) in
                        try await client.search(query, cursor: nil)
                    }
                    state = .loaded(page.items.map { RemotePublication($0, server: id) })
                } catch {
                    state = .failed(DisplayError(error))
                }
                guard current == generation, let index = results.firstIndex(where: { $0.account == id }) else { return }
                results[index].state = state
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
}

private struct SearchResults: View {
    let text: String
    let serverResults: ServerSearchModel
    @Query private var books: [Book]

    init(text: String, serverResults: ServerSearchModel) {
        self.text = text
        self.serverResults = serverResults
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<Book>(
            predicate: Book.predicate(kind: nil, search: trimmed),
            sortBy: [SortDescriptor(\.title, comparator: .localizedStandard)]
        )
        // An empty search would list the whole library.
        descriptor.fetchLimit = trimmed.isEmpty ? 0 : 50
        _books = Query(descriptor)
    }

    var body: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState("Search Everything", systemImage: "magnifyingglass", description: Text("Look for books, comics and authors in your library, shared libraries and sites."))
        } else if books.isEmpty && serverResults.isEmpty {
            ContentUnavailableView.search(text: text)
        } else {
            List {
                if !books.isEmpty {
                    Section("Your Library") {
                        ForEach(books) { book in
                            SearchBookRow(book: book)
                        }
                    }
                }
                // What was found comes first; a server that couldn't be
                // reached says so after it, not above it.
                ForEach(serverResults.results.sorted { !$0.state.isFailed && $1.state.isFailed }) { results in
                    ServerResultsSection(results: results)
                }
                ForEach(serverResults.sourceResults.sorted { !$0.state.isFailed && $1.state.isFailed }) { results in
                    SourceResultsSection(results: results)
                }
            }
        }
    }
}

private struct SearchBookRow: View {
    let book: Book
    @State private var bookToRemove: Book?

    var body: some View {
        PublicationRow(item: PublicationItem(book))
            .contextMenu {
                BookActions(book: book, bookToRemove: $bookToRemove)
            }
            .removeBookConfirmation(book: $bookToRemove)
    }
}

private struct ServerResultsSection: View {
    let results: ServerSearchModel.Results
    @Query private var states: [RemoteReadingState]
    @Environment(ServerStore.self) private var servers

    init(results: ServerSearchModel.Results) {
        self.results = results
        _states = Query(filter: RemoteReadingState.onServer(results.account))
    }

    var body: some View {
        switch results.state {
        case .idle:
            EmptyView()
        case .loading:
            Section(results.name) {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        case .failed(let error):
            Section(results.name) {
                Label(error.title, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        case .loaded(let publications):
            if !publications.isEmpty {
                let statuses = ReadingStatuses(states)
                Section(results.name) {
                    ForEach(publications) { publication in
                        PublicationRow(item: servers.item(publication, status: statuses[publication.id]))
                    }
                }
            }
        }
    }
}

extension ServerSearchModel {
    /// Whether no server found anything, counting ones still searching as
    /// not empty so the "no results" screen doesn't flash.
    var isEmpty: Bool {
        results.allSatisfy { results in
            if case .loaded(let items) = results.state { items.isEmpty } else { false }
        } && sourceResults.allSatisfy { results in
            if case .loaded(let items) = results.state { items.isEmpty } else { false }
        }
    }
}

/// A source's series as a row of covers, as a store's search shows them,
/// since there are often many and covers tell them apart fastest.
private struct SourceResultsSection: View {
    let results: ServerSearchModel.SourceResults

    var body: some View {
        switch results.state {
        case .idle:
            EmptyView()
        case .loading:
            Section(header) {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        case .failed(let error):
            Section(header) {
                Label(error.title, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        case .loaded(let series):
            if !series.isEmpty {
                Section(header) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: Metrics.coverSpacing) {
                            ForEach(series) { item in
                                SourceSeriesCell(account: results.account, source: results.source.id, series: item)
                                    .frame(width: Metrics.shelfCoverWidth(regular: false))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: Metrics.margin, bottom: 8, trailing: 0))
                }
            }
        }
    }

    private var header: String {
        "\(results.source.name) · \(results.serverName)"
    }
}
