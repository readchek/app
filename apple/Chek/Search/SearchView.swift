import SwiftData
import SwiftUI

/// Looks through everything at once, or through one place.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ServerStore.self) private var servers
    @State private var text = ""
    @State private var filters = SearchFilters()
    @State private var serverResults = ServerSearchModel()
    @State private var recents = RecentSearches()

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.searchPath) {
            Group {
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    RecentSearchesView(recents: recents) { query in
                        text = query
                    }
                } else {
                    SearchResults(text: text, filters: $filters, serverResults: serverResults, servers: servers)
                        .environment(\.searchSites, serverResults.sites)
                }
            }
            .demoBanner()
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SearchFilterMenu(filters: $filters, sites: serverResults.sites)
                }
            }
            .routeDestinations()
        }
        .searchable(text: $text, prompt: prompt)
        .onSubmit(of: .search) {
            recents.add(text)
        }
        .onChange(of: router.searchPath.count) { old, new in
            // Opening a result is as good as pressing Search: it was the
            // search you meant.
            if new > old {
                recents.add(text)
            }
        }
        .task {
            // The sites are listed early so the filter menu can offer them.
            await serverResults.loadSites(servers: servers)
        }
        // Searched again when the content ratings change, since they
        // decide which series the sites answer with.
        .task(id: SearchRequest(text: text, filters: filters, revision: servers.contentRatingsRevision)) {
            // Waiting for a pause in typing keeps servers from getting a
            // request per keystroke. A new keystroke cancels the wait.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await serverResults.search(text, filters: filters, servers: servers)
        }
    }

    /// Names the one place being searched, so it's plain where the
    /// results come from.
    private var prompt: Text {
        switch filters.scope {
        case .everywhere:
            Text("Books, Comics, and Authors")
        case .library:
            Text("Search Your Library")
        case .server(let id):
            Text("Search \(servers.accounts().first { $0.id == id }?.name ?? "")")
        case .source(let server, let id):
            Text("Search \(serverResults.sites[server]?.first { $0.id == id }?.name ?? "")")
        }
    }
}

extension EnvironmentValues {
    /// Each shared library's sites, for naming the one being searched.
    @Entry fileprivate var searchSites: [UUID: [ChekAPI.InstalledExtension]] = [:]
}

/// What a search is for, so changing any of it searches again.
private struct SearchRequest: Equatable {
    var text: String
    var filters: SearchFilters
    var revision: Int
}

private struct SearchResults: View {
    let text: String
    @Binding var filters: SearchFilters
    let serverResults: ServerSearchModel
    let servers: ServerStore
    @Query private var books: [Book]

    init(text: String, filters: Binding<SearchFilters>, serverResults: ServerSearchModel, servers: ServerStore) {
        self.text = text
        _filters = filters
        self.serverResults = serverResults
        self.servers = servers
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<Book>(
            predicate: Book.predicate(kind: filters.wrappedValue.kind, search: trimmed),
            sortBy: [SortDescriptor(\.title, comparator: .localizedStandard)]
        )
        descriptor.fetchLimit = filters.wrappedValue.scope == .library ? 500 : 50
        _books = Query(descriptor)
    }

    var body: some View {
        switch filters.scope {
        case .everywhere:
            EverywhereResults(text: text, filters: $filters, books: books, serverResults: serverResults, servers: servers)
        case .library:
            ScopedGrid(filters: $filters, state: .loaded(books.map(PublicationItem.init)), text: text)
        case .server(let id):
            ServerGrid(account: id, text: text, filters: $filters, serverResults: serverResults, servers: servers)
        case .source(let server, let id):
            SourceGrid(id: "\(server.uuidString)/\(id)", text: text, filters: $filters, serverResults: serverResults, servers: servers)
        }
    }
}

/// Everywhere at once: a shelf for each place that found something, added
/// as each answers, so places with nothing take no room.
private struct EverywhereResults: View {
    let text: String
    @Binding var filters: SearchFilters
    let books: [Book]
    let serverResults: ServerSearchModel
    let servers: ServerStore

    var body: some View {
        let found = serverResults.found
        let searching = serverResults.searching
        let failures = serverResults.failures
        let isEmpty = books.isEmpty && found.isEmpty
        List {
            ActiveFilters(filters: $filters)
            if !books.isEmpty {
                Section {
                    ResultsShelf(items: books.map(PublicationItem.init))
                } header: {
                    PlaceHeader(title: "Library") { filters.scope = .library }
                }
            }
            ForEach(found) { place in
                switch place {
                case .server(let results):
                    ServerResultsSection(results: results) { filters.scope = .server(results.account) }
                case .source(let results):
                    SourceResultsSection(results: results) { filters.scope = .source(results.account, results.source.id) }
                }
            }
            if isEmpty && !searching.isEmpty {
                // Room for the first answer while every place is looking.
                PlaceholderShelf()
                    .searchShelfRow()
                    .listRowSeparator(.hidden)
            }
            if !searching.isEmpty {
                StillSearchingRow(names: searching)
            }
            ForEach(failures) { place in
                failureRow(place)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if isEmpty && searching.isEmpty && failures.isEmpty {
                // Below the filters, which stay usable.
                ContentUnavailableView.search(text: text)
                    .padding(.top, 56)
            }
        }
        .animation(.default, value: found.map(\.id))
    }

    @ViewBuilder
    private func failureRow(_ place: ServerSearchModel.Found) -> some View {
        switch place {
        case .server(let results):
            if case .failed(let error) = results.state {
                SectionFailureRow(place: results.name, error: error) {
                    await serverResults.retry(server: results.account, servers: servers)
                }
            }
        case .source(let results):
            if case .failed(let error) = results.state {
                SectionFailureRow(place: results.source.name, error: error) {
                    await serverResults.retry(source: results.id, servers: servers)
                }
            }
        }
    }
}

/// A section's title, with the way to see everything it found.
private struct PlaceHeader: View {
    let title: String
    let seeAll: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("See All", action: seeAll)
                .font(.subheadline)
                .buttonStyle(.borderless)
        }
        .textCase(nil)
    }
}

/// The places still looking, below what's been found so far.
private struct StillSearchingRow: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Searching \(names.formatted(.list(type: .and)))…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .listRowSeparator(.hidden)
    }
}

/// A place whose search failed, with the way to try it again.
private struct SectionFailureRow: View {
    let place: String
    let error: DisplayError
    let retry: () async -> Void

    var body: some View {
        HStack {
            Label("Couldn't search \(place)", systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Try Again") {
                Task { await retry() }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .listRowSeparator(.hidden)
        .accessibilityHint(Text(error.title))
    }
}

private struct ServerResultsSection: View {
    let results: ServerSearchModel.Results
    let seeAll: () -> Void
    @Query private var states: [RemoteReadingState]
    @Environment(ServerStore.self) private var servers

    init(results: ServerSearchModel.Results, seeAll: @escaping () -> Void) {
        self.results = results
        self.seeAll = seeAll
        _states = Query(filter: RemoteReadingState.onServer(results.account))
    }

    var body: some View {
        if let publications = results.state.value {
            Section {
                let statuses = ReadingStatuses(states)
                ResultsShelf(items: publications.map { servers.item($0, status: statuses[$0.id]) })
            } header: {
                PlaceHeader(title: results.name, seeAll: seeAll)
            }
        }
    }
}

/// A source's series as a row of covers, as a store's search shows them,
/// since there are often many and covers tell them apart fastest.
private struct SourceResultsSection: View {
    let results: ServerSearchModel.SourceResults
    let seeAll: () -> Void

    var body: some View {
        if let series = results.state.value {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.coverSpacing) {
                        ForEach(series) { item in
                            SourceSeriesCell(account: results.account, source: results.source.id, series: item)
                                .shelfCell()
                        }
                    }
                    .scrollTargetLayout()
                }
                // The row spans the screen and the shelf keeps its own
                // margins, so its cells are the size of a grid's.
                .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .searchShelfRow()
            } header: {
                PlaceHeader(title: results.source.name, seeAll: seeAll)
            }
        }
    }
}

/// Found books and comics as a row of covers, as every section of the
/// results shows what it found.
private struct ResultsShelf: View {
    let items: [PublicationItem]
    @State private var bookToRemove: Book?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Metrics.coverSpacing) {
                ForEach(items) { item in
                    PublicationCell(item: item)
                        .shelfCell()
                        // A book here has the menu it has in Library.
                        .contextMenu {
                            if case .local(let book) = item.source {
                                BookActions(book: book, bookToRemove: $bookToRemove)
                            }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .searchShelfRow()
        .removeBookConfirmation(book: $bookToRemove)
    }
}

extension View {
    /// A shelf as a row of the results list: edge to edge, with the same
    /// room above and below in every section.
    fileprivate func searchShelfRow() -> some View {
        padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
}

// MARK: - One place

/// Above the results: the way to narrow them, since the toolbar is hidden
/// while typing, then each filter in use with the way to take it off, so
/// a narrowed search never looks like everything there is.
private struct ActiveFilters: View {
    @Binding var filters: SearchFilters
    @Environment(ServerStore.self) private var servers
    @Environment(\.searchSites) private var sites

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    SearchFilterOptions(filters: $filters, sites: sites)
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                if filters.scope != .everywhere {
                    token(scopeName) { filters.scope = .everywhere }
                }
                if let kind = filters.kind {
                    token(kind == .book ? String(localized: "Books") : String(localized: "Comics")) { filters.kind = nil }
                }
            }
            .padding(.horizontal, Metrics.margin)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
    }

    private func token(_ title: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(Text("Remove \(title) Filter"))
    }

    private var scopeName: String {
        switch filters.scope {
        case .everywhere: ""
        case .library: String(localized: "Library")
        case .server(let id): servers.accounts().first { $0.id == id }?.name ?? ""
        case .source(let server, let id): sites[server]?.first { $0.id == id }?.name ?? id
        }
    }
}

/// One place's results as a grid of covers, with more as you scroll.
private struct ScopedGrid: View {
    @Binding var filters: SearchFilters
    let state: LoadState<[PublicationItem]>
    let text: String
    var retry: (() async -> Void)?
    var loadMore: (() async -> Void)?
    var isLoadingMore = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            ActiveFilters(filters: $filters)
                .padding(.vertical, 8)
            switch state {
            case .idle, .loading:
                PlaceholderGrid()
            case .loaded(let items):
                LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
                    ForEach(items) { item in
                        PublicationCell(item: item)
                            .task {
                                if item.id == items.last?.id { await loadMore?() }
                            }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.vertical, 8)
                if isLoadingMore {
                    ProgressView()
                        .padding()
                }
            case .failed:
                EmptyView()
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            switch state {
            case .failed(let error):
                FailureState(error: error, retry: retry)
                    .padding(.top, 56)
            case .loaded(let items) where items.isEmpty:
                ContentUnavailableView.search(text: text)
                    .padding(.top, 56)
            default:
                EmptyView()
            }
        }
    }
}

private struct ServerGrid: View {
    let account: UUID
    let text: String
    @Binding var filters: SearchFilters
    let serverResults: ServerSearchModel
    let servers: ServerStore
    @Query private var states: [RemoteReadingState]

    init(account: UUID, text: String, filters: Binding<SearchFilters>, serverResults: ServerSearchModel, servers: ServerStore) {
        self.account = account
        self.text = text
        _filters = filters
        self.serverResults = serverResults
        self.servers = servers
        _states = Query(filter: RemoteReadingState.onServer(account))
    }

    var body: some View {
        let results = serverResults.results.first { $0.account == account }
        let statuses = ReadingStatuses(states)
        let state: LoadState<[PublicationItem]> = switch results?.state ?? .loading {
        case .idle, .loading: .loading
        case .failed(let error): .failed(error)
        case .loaded(let publications): .loaded(publications.map { servers.item($0, status: statuses[$0.id]) })
        }
        ScopedGrid(
            filters: $filters,
            state: state,
            text: text,
            retry: { await serverResults.retry(server: account, servers: servers) },
            loadMore: { await serverResults.loadMore(server: account, servers: servers) },
            isLoadingMore: serverResults.isLoadingMore
        )
    }
}

private struct SourceGrid: View {
    let id: String
    let text: String
    @Binding var filters: SearchFilters
    let serverResults: ServerSearchModel
    let servers: ServerStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let results = serverResults.sourceResults.first { $0.id == id }
        ScrollView {
            ActiveFilters(filters: $filters)
                .padding(.vertical, 8)
            if let results, let series = results.state.value {
                LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
                    ForEach(series) { item in
                        SourceSeriesCell(account: results.account, source: results.source.id, series: item)
                            .task {
                                if item.id == series.last?.id {
                                    await serverResults.loadMore(source: id, servers: servers)
                                }
                            }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.vertical, 8)
                if serverResults.isLoadingMore {
                    ProgressView()
                        .padding()
                }
            } else if results?.state.isFailed != true {
                PlaceholderGrid()
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            switch results?.state {
            case .failed(let error):
                FailureState(error: error) { await serverResults.retry(source: id, servers: servers) }
                    .padding(.top, 56)
            case .loaded(let series) where series.isEmpty:
                ContentUnavailableView.search(text: text)
                    .padding(.top, 56)
            default:
                EmptyView()
            }
        }
    }
}

/// Where to search and what to show, from the toolbar.
private struct SearchFilterMenu: View {
    @Binding var filters: SearchFilters
    let sites: [UUID: [ChekAPI.InstalledExtension]]

    var body: some View {
        Menu {
            SearchFilterOptions(filters: $filters, sites: sites)
        } label: {
            Label("Filters", systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}

/// The choices of where to search and what to show, for a menu.
private struct SearchFilterOptions: View {
    @Binding var filters: SearchFilters
    let sites: [UUID: [ChekAPI.InstalledExtension]]
    @Environment(ServerStore.self) private var servers

    var body: some View {
        let accounts = servers.accounts().filter { servers.state(of: $0.id) == .signedIn }
        Section("Show") {
            Picker("Show", selection: $filters.kind) {
                Text("Books and Comics").tag(PublicationKind?.none)
                Label("Books", systemImage: "book").tag(PublicationKind?.some(.book))
                Label("Comics", systemImage: "book.pages").tag(PublicationKind?.some(.comic))
            }
            .pickerStyle(.inline)
        }
        Section("Search In") {
            Picker("Search In", selection: $filters.scope) {
                Label("Everywhere", systemImage: "magnifyingglass").tag(SearchScope.everywhere)
                Label("Library", systemImage: "books.vertical").tag(SearchScope.library)
                ForEach(accounts) { account in
                    Label(account.name, systemImage: "person.2").tag(SearchScope.server(account.id))
                }
                ForEach(accounts) { account in
                    // Only sites that have what's chosen to show.
                    ForEach((sites[account.id] ?? []).filter { SearchFilters.source($0, matches: filters.kind) }) { site in
                        // With more than one shared library, a site says
                        // which it was added to.
                        if accounts.count > 1 {
                            Label {
                                Text(site.name)
                                Text(account.name)
                            } icon: {
                                Image(systemName: "globe")
                            }
                            .tag(SearchScope.source(account.id, site.id))
                        } else {
                            Label(site.name, systemImage: "globe").tag(SearchScope.source(account.id, site.id))
                        }
                    }
                }
            }
            .pickerStyle(.inline)
        }
    }
}
