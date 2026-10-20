import SwiftData
import SwiftUI

/// A server library's series as a grid of covers, loaded as you scroll.
struct ServerLibraryView: View {
    let account: UUID
    let library: ChekAPI.Library
    @Environment(ServerStore.self) private var servers
    @State private var series: PagedList<ChekAPI.Series>?
    @State private var query = ""
    /// The query the results are for, which changes once you pause.
    @State private var submittedQuery = ""
    @State private var found: PagedList<RemotePublication>?

    var body: some View {
        Group {
            if !submittedQuery.isEmpty, let found {
                LibrarySearchResults(account: account, query: submittedQuery, found: found)
            } else if let series {
                SeriesGrid(account: account, series: series)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(library.name)
        // Only this library, so a big one can be searched without the
        // other servers answering too.
        // Always shown: hidden under the title until pulled, nobody would
        // know a library can be searched.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search \(library.name)"))
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            submittedQuery = trimmed
        }
        .task(id: submittedQuery) {
            guard !submittedQuery.isEmpty else {
                found = nil
                return
            }
            let list = makeSearch(submittedQuery)
            found = list
            await list.loadIfNeeded()
        }
        .task(id: library.id) {
            let list = series ?? makeList()
            series = list
            await list.loadIfNeeded()
        }
    }

    private func makeSearch(_ query: String) -> PagedList<RemotePublication> {
        let servers = servers
        let account = account
        let library = library.id
        return PagedList { cursor in
            let page = try await servers.request(account) { client throws(ChekError) in
                try await client.search(query, inLibrary: library, cursor: cursor)
            }
            return (page.items.map { RemotePublication($0, server: account) }, page.nextCursor)
        }
    }

    private func makeList() -> PagedList<ChekAPI.Series> {
        let servers = servers
        let account = account
        let library = library.id
        return PagedList { cursor in
            let page = try await servers.request(account) { client throws(ChekError) in
                try await client.series(inLibrary: library, cursor: cursor)
            }
            return (page.items, page.nextCursor)
        }
    }
}

private struct SeriesGrid: View {
    let account: UUID
    let series: PagedList<ChekAPI.Series>
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            if let error = series.staleError {
                StaleNotice(error: error)
                    .padding(.top, 8)
            }
            LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
                ForEach(series.items) { item in
                    SeriesCell(account: account, series: item)
                        .task {
                            await series.loadMore(after: item)
                        }
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 8)
            if series.phase == .loadingMore {
                ProgressView()
                    .padding()
            }
        }
        .overlay {
            PagedListOverlay(phase: series.phase, isEmpty: series.items.isEmpty, emptyTitle: "No Series") {
                Task { await series.reload() }
            }
        }
        .refreshable {
            await series.reload()
        }
    }
}

/// What a search of one library found, as rows.
private struct LibrarySearchResults: View {
    let account: UUID
    let query: String
    let found: PagedList<RemotePublication>
    @Query private var states: [RemoteReadingState]
    @Environment(ServerStore.self) private var servers

    init(account: UUID, query: String, found: PagedList<RemotePublication>) {
        self.account = account
        self.query = query
        self.found = found
        _states = Query(filter: RemoteReadingState.onServer(account))
    }

    var body: some View {
        let statuses = ReadingStatuses(states)
        List {
            ForEach(found.items) { publication in
                PublicationRow(item: servers.item(publication, status: statuses[publication.id]))
                    .task {
                        await found.loadMore(after: publication)
                    }
            }
            if found.phase == .loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if found.phase == .complete, found.items.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                PagedListOverlay(phase: found.phase, isEmpty: found.items.isEmpty, emptyTitle: "No Results") {
                    Task { await found.reload() }
                }
            }
        }
    }
}

/// A series' cover with its title and how many items it has, drawn like
/// ``PublicationCell`` so grids of either look the same.
private struct SeriesCell: View {
    let account: UUID
    let series: ChekAPI.Series
    @Environment(ServerStore.self) private var servers

    var body: some View {
        NavigationLink(value: Route.series(account, seriesID: series.id, title: series.displayTitle)) {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(
                    source: series.coverPublicationId.map { servers.cover(of: $0, on: account) } ?? .none,
                    title: series.displayTitle
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.displayTitle)
                        .font(.footnote.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                    Text("^[\(series.publicationCount) item](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The loading, failed and empty states shared by paged screens.
struct PagedListOverlay: View {
    let phase: PagedListPhase
    let isEmpty: Bool
    let emptyTitle: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .failed(let error) where isEmpty:
            ContentUnavailableView {
                Label(error.title, systemImage: "wifi.exclamationmark")
            } description: {
                if let message = error.message {
                    Text(message)
                }
            } actions: {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        case .complete where isEmpty:
            ContentUnavailableView(emptyTitle, systemImage: "books.vertical")
        default:
            EmptyView()
        }
    }
}
