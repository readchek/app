import SwiftData
import SwiftUI

/// A series on a server: a header with a button to read on from where
/// you are, then every volume or chapter in order.
struct SeriesView: View {
    let account: UUID
    let seriesID: Int64
    let title: String
    @Environment(ServerStore.self) private var servers
    @State private var publications: PagedList<RemotePublication>?

    var body: some View {
        Group {
            if let publications {
                SeriesContent(account: account, seriesID: seriesID, title: title, publications: publications)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: seriesID) {
            let list = publications ?? makeList()
            publications = list
            await list.loadIfNeeded()
        }
    }

    private func makeList() -> PagedList<RemotePublication> {
        let servers = servers
        let account = account
        let series = seriesID
        return PagedList { cursor in
            let page = try await servers.request(account) { client throws(ChekError) in
                try await client.publications(inSeries: series, cursor: cursor)
            }
            return (page.items.map { RemotePublication($0, server: account) }, page.nextCursor)
        }
    }
}

private struct SeriesContent: View {
    let account: UUID
    let title: String
    let publications: PagedList<RemotePublication>
    @Query private var states: [RemoteReadingState]

    init(account: UUID, seriesID: Int64, title: String, publications: PagedList<RemotePublication>) {
        self.account = account
        self.title = title
        self.publications = publications
        _states = Query(filter: #Predicate<RemoteReadingState> { $0.serverID == account && $0.seriesID == seriesID })
    }

    var body: some View {
        let statuses = ReadingStatuses(states)
        List {
            if let first = publications.items.first {
                SeriesHeader(
                    title: title,
                    count: publications.items.count,
                    isComplete: publications.phase == .complete,
                    cover: first,
                    next: nextToRead(statuses: statuses)
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
            ForEach(publications.items) { publication in
                RemotePublicationRow(publication: publication, status: statuses[publication.id], showsSeries: false)
                    .task {
                        await publications.loadMore(after: publication)
                    }
            }
            if publications.phase == .loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            PagedListOverlay(phase: publications.phase, isEmpty: publications.items.isEmpty, emptyTitle: "Nothing in This Series") {
                Task { await publications.reload() }
            }
        }
        .refreshable {
            await publications.reload()
        }
    }

    /// The one you're partway through, or else the first you haven't finished.
    private func nextToRead(statuses: ReadingStatuses) -> (RemotePublication, ReadingStatus)? {
        let items = publications.items
        if let started = items.last(where: { if case .inProgress = statuses[$0.id] { true } else { false } }) {
            return (started, statuses[started.id])
        }
        let lastFinished = items.lastIndex { statuses[$0.id] == .finished }
        let next = lastFinished.map { items.index(after: $0) } ?? items.startIndex
        guard items.indices.contains(next) else { return nil }
        return (items[next], statuses[items[next].id])
    }
}

private struct SeriesHeader: View {
    let title: String
    let count: Int
    let isComplete: Bool
    let cover: RemotePublication
    let next: (RemotePublication, ReadingStatus)?
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            CoverView(source: servers.cover(of: cover.id, on: cover.server), title: title, cornerRadius: 8)
                .frame(width: 150)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(isComplete ? "^[\(count) item](inflect: true)" : "\(count)+ items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let (publication, status) = next {
                Button {
                    router.open(publication, using: sync)
                } label: {
                    VStack(spacing: 2) {
                        Text(status == .new ? "Start Reading" : "Continue")
                            .font(.headline)
                        Text(publication.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 320)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}
