import SwiftData
import SwiftUI

/// A series on a server: its cover and a button to read on from where you
/// are, then every volume or chapter in order.
struct SeriesView: View {
    let account: UUID
    let seriesID: Int64
    let title: String
    /// How many books the library said the series has.
    let count: Int
    @State private var isHeaderVisible = true
    @Environment(ServerStore.self) private var servers
    @State private var publications: PagedList<RemotePublication>?

    var body: some View {
        Group {
            if let publications {
                SeriesContent(account: account, seriesID: seriesID, title: title, count: count, publications: publications)
            } else {
                LoadingState()
            }
        }
        // The header shows the title large, so the bar only takes it once
        // the header has scrolled away, as Music does for albums.
        .navigationTitle(isHeaderVisible ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .onPreferenceChange(SeriesHeaderVisibleKey.self) { visible in
            withAnimation(.easeInOut(duration: 0.2)) { isHeaderVisible = visible }
        }
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
    @State private var headerVisible = true
    let account: UUID
    let title: String
    let count: Int
    let publications: PagedList<RemotePublication>
    @Query private var states: [RemoteReadingState]
    @Environment(ServerStore.self) private var servers
    @Environment(Downloads.self) private var downloads

    init(account: UUID, seriesID: Int64, title: String, count: Int, publications: PagedList<RemotePublication>) {
        self.account = account
        self.title = title
        self.count = count
        self.publications = publications
        _states = Query(filter: #Predicate<RemoteReadingState> { $0.serverID == account && $0.seriesID == seriesID })
    }

    var body: some View {
        let statuses = ReadingStatuses(states)
        List {
            if let error = publications.staleError {
                StaleNotice(error: error)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            if let first = publications.items.first {
                Section {
                    SeriesHeader(
                        title: title,
                        // What's loaded once that's all of it, since books may
                        // have been added since the library was listed.
                        count: publications.phase == .complete ? publications.items.count : max(count, publications.items.count),
                        areComics: publications.items.allSatisfy { $0.kind == .comic },
                        cover: servers.cover(of: first.id, on: first.server),
                        next: nextToRead(statuses: statuses),
                        comics: publications.items.filter { $0.kind == .comic && $0.isAvailable },
                        unreadComics: publications.items.filter { $0.kind == .comic && $0.isAvailable && statuses[$0.id] != .finished }
                    )
                    .listRowSeparator(.hidden)
                    .onScrollVisibilityChange(threshold: 0.2) { visible in
                        headerVisible = visible
                    }
                    .preference(key: SeriesHeaderVisibleKey.self, value: headerVisible)
                }
                // On the sections, not the row: the lines around the
                // header are the sections' own.
                .listSectionSeparator(.hidden)
            }
            Section {
                ForEach(publications.items) { publication in
                    PublicationRow(item: servers.item(publication, status: statuses[publication.id], showsSeries: false))
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
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
        .overlay {
            PagedListOverlay(phase: publications.phase, isEmpty: publications.items.isEmpty, emptyMessage: "This series is empty.", placeholder: .spinner) {
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

/// The series' cover beside its title, and the button that picks up where
/// you are.
private struct SeriesHeader: View {
    let title: String
    let count: Int
    /// Whether every book of it seen so far is a comic.
    let areComics: Bool
    let cover: CoverSource
    let next: (RemotePublication, ReadingStatus)?
    /// The comics in the series, which can be kept on the device.
    let comics: [RemotePublication]
    let unreadComics: [RemotePublication]
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(Downloads.self) private var downloads
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isConfirmingAll = false

    var body: some View {
        let isRegular = sizeClass == .regular
        VStack(alignment: .leading, spacing: 16) {
            // Title beside the top of the cover, as Books and Music lay
            // out a title page.
            HStack(alignment: .top, spacing: 16) {
                CoverView(source: cover, title: title)
                    .frame(width: Metrics.headerCoverWidth(regular: isRegular))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(3)
                    Text(count: count, areComics: areComics)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // Two buttons of one size, as Books pairs "Want to Read" and
            // "Read"; style, not width, says which one matters.
            HStack(spacing: 12) {
                if let (publication, status) = next {
                    Button {
                        router.open(publication, using: sync)
                    } label: {
                        Text(ContinueLabel.text(for: publication.displayTitle, isNew: status == .new))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !comics.isEmpty {
                    downloadsMenu
                }
            }
            .buttonBorderShape(.capsule)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    /// Keeping the series' comics on the device, a few or all at once.
    private var downloadsMenu: some View {
        let kept = comics.filter { downloads.isDownloaded($0.ref) }
        let pending = unreadComics.filter { downloads.state(of: $0.ref) == .none }
        return Menu {
            Section("Download") {
                if pending.isEmpty {
                    // Read or already here, every one of them.
                    Button("Nothing Left to Download", systemImage: "checkmark.circle") {}
                        .disabled(true)
                } else {
                    Button("Next \(min(pending.count, 5)) Unread", systemImage: "arrow.down.circle") {
                        downloads.download(pending.prefix(5).map(Downloads.Item.comic))
                    }
                }
                Button("All Unread", systemImage: "arrow.down.circle.fill") {
                    if pending.count > 10 {
                        isConfirmingAll = true
                    } else {
                        downloads.download(pending.map(Downloads.Item.comic))
                    }
                }
                // Pointless when the next few are all there are.
                .disabled(pending.count <= 5)
            }
            if !kept.isEmpty {
                Divider()
                Button("Remove ^[\(kept.count) Download](inflect: true)", systemImage: "trash", role: .destructive) {
                    downloads.remove(kept.map(Downloads.Item.comic))
                }
            }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .confirmationDialog("Download ^[\(pending.count) Comic](inflect: true)?", isPresented: $isConfirmingAll, titleVisibility: .visible) {
            Button("Download All") {
                downloads.download(pending.map(Downloads.Item.comic))
            }
        } message: {
            Text("They download one at a time while Chek is open and stay on this device until you remove them.")
        }
    }
}

extension Text {
    /// "12 comics" for a series of comics, "12 books" for one of books or
    /// of both.
    init(count: Int, areComics: Bool) {
        if areComics {
            self.init("^[\(count) comic](inflect: true)")
        } else {
            self.init("^[\(count) book](inflect: true)")
        }
    }
}
