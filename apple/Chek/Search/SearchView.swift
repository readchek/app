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

    private(set) var results: [Results] = []
    @ObservationIgnored private var generation = 0

    func search(_ text: String, servers: ServerStore) async {
        generation += 1
        let current = generation
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let accounts = servers.accounts().filter { servers.state(of: $0.id) == .signedIn }
        guard !query.isEmpty else {
            results = []
            return
        }
        results = accounts.map { Results(account: $0.id, name: $0.name, state: .loading) }
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
        } onCancel: {
            for task in tasks {
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
            ContentUnavailableView("Search Everything", systemImage: "magnifyingglass", description: Text("Find books and comics on this device and your servers by title, series or author."))
        } else if books.isEmpty && serverResults.isEmpty {
            ContentUnavailableView.search(text: text)
        } else {
            List {
                if !books.isEmpty {
                    Section("On This Device") {
                        ForEach(books) { book in
                            SearchBookRow(book: book)
                        }
                    }
                }
                ForEach(serverResults.results) { results in
                    ServerResultsSection(results: results)
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
        }
    }
}
