import SwiftUI

/// A source's series as a grid of covers: what it shows first, or what
/// matches your search, loaded a page at a time as you scroll.
struct SourceView: View {
    let account: UUID
    let source: ChekAPI.InstalledExtension
    @Environment(ServerStore.self) private var servers
    @State private var query = ""
    /// The query the list was made for, which only changes once you stop
    /// typing, so each keystroke doesn't send the source to its site.
    @State private var submittedQuery = ""
    @State private var series: PagedList<ChekAPI.SourceSeriesItem>?

    var body: some View {
        Group {
            if !source.usable {
                ContentUnavailableView(
                    "Not Allowed on This Server",
                    systemImage: "lock",
                    description: Text("This source comes from a repository the server's admin hasn't allowed.")
                )
            } else if let series {
                SourceSeriesGrid(account: account, source: source.id, series: series, isSearching: !submittedQuery.isEmpty)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(source.name)
        .searchable(text: $query, prompt: Text("Search \(source.name)"))
        .onSubmit(of: .search) {
            submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .task(id: query) {
            // Searches after a pause in typing, and at once when cleared.
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            submittedQuery = trimmed
        }
        .task(id: submittedQuery) {
            guard source.usable else { return }
            let list = makeList(query: submittedQuery)
            series = list
            await list.loadIfNeeded()
        }
    }

    private func makeList(query: String) -> PagedList<ChekAPI.SourceSeriesItem> {
        let servers = servers
        let account = account
        let source = source.id
        return PagedList { cursor in
            // The cursor is the next page's number; sources count from 1.
            let page = cursor.flatMap(Int.init) ?? 1
            let result = try await servers.request(account) { client throws(ChekError) in
                try await client.search(source: source, query: query, page: page)
            }
            return (result.items, result.hasMore && !result.items.isEmpty ? String(page + 1) : nil)
        }
    }
}

private struct SourceSeriesGrid: View {
    let account: UUID
    let source: String
    let series: PagedList<ChekAPI.SourceSeriesItem>
    let isSearching: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            if let error = series.staleError {
                StaleNotice(error: error)
                    .padding(.top, 8)
            }
            LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
                ForEach(series.items) { item in
                    SourceSeriesCell(account: account, source: source, series: item)
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
            if isSearching, series.phase == .complete, series.items.isEmpty {
                ContentUnavailableView.search
            } else {
                PagedListOverlay(phase: series.phase, isEmpty: series.items.isEmpty, emptyTitle: "No Series") {
                    Task { await series.reload() }
                }
            }
        }
        .refreshable {
            await series.reload()
        }
    }
}

/// A source's series drawn like the other grids' cells.
struct SourceSeriesCell: View {
    let account: UUID
    let source: String
    let series: ChekAPI.SourceSeriesItem
    @Environment(ServerStore.self) private var servers

    var body: some View {
        NavigationLink(value: Route.sourceSeries(account, source: source, seriesID: series.id, title: series.title)) {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(source: servers.sourceImage(series.coverUrl, on: account), title: series.title)
                Text(series.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
