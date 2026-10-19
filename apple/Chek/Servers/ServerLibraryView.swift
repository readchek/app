import SwiftUI

/// A server library's series as a grid of covers, loaded as you scroll.
struct ServerLibraryView: View {
    let account: UUID
    let library: ChekAPI.Library
    @Environment(ServerStore.self) private var servers
    @State private var series: PagedList<ChekAPI.Series>?

    var body: some View {
        Group {
            if let series {
                SeriesGrid(account: account, series: series)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(library.name)
        .task(id: library.id) {
            let list = series ?? makeList()
            series = list
            await list.loadIfNeeded()
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

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20, alignment: .top)], spacing: 28) {
                ForEach(series.items) { item in
                    SeriesTile(account: account, series: item)
                        .task {
                            await series.loadMore(after: item)
                        }
                }
            }
            .padding()
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

private struct SeriesTile: View {
    let account: UUID
    let series: ChekAPI.Series
    @Environment(ServerStore.self) private var servers

    var body: some View {
        NavigationLink(value: Route.series(account, seriesID: series.id, title: series.title)) {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(
                    source: series.coverPublicationId.map { servers.cover(of: $0, on: account) } ?? .none,
                    title: series.title
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
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
                    .buttonStyle(.glass)
            }
        case .complete where isEmpty:
            ContentUnavailableView(emptyTitle, systemImage: "books.vertical")
        default:
            EmptyView()
        }
    }
}
