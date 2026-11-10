import SwiftData
import SwiftUI

/// The series you follow: every chapter of theirs you haven't seen yet,
/// newest first across all of them, then the series themselves, so the
/// Following shelf's header leads to all of what it shows a row of.
struct UpdatesView: View {
    @Query(sort: \FollowedSeries.followedAt, order: .reverse) private var follows: [FollowedSeries]
    @Environment(FollowStore.self) private var followStore
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router
    @State private var entries: LoadState<[Entry]> = .idle
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// One new chapter, with the series it's in.
    struct Entry: Identifiable {
        let follow: FollowedSeries
        let chapter: ChekAPI.SourceChapter
        let published: Date?

        var id: String { follow.key + "/" + chapter.id }

        var ref: SourceChapterRef {
            SourceChapterRef(
                server: follow.serverID,
                source: follow.sourceID,
                seriesID: follow.seriesID,
                seriesTitle: follow.title,
                chapterID: chapter.id,
                chapterTitle: chapter.displayTitle,
                isRightToLeft: follow.isRightToLeft,
                seriesCoverPath: follow.coverPath
            )
        }
    }

    var body: some View {
        Group {
            switch entries {
            case .idle, .loading:
                LoadingState()
            case .failed(let error):
                FailureState(error: error) {
                    await load()
                }
            case .loaded where follows.isEmpty:
                EmptyState("Series you follow appear here, with their new chapters.", systemImage: "bell")
            case .loaded(let entries):
                List {
                    if entries.isEmpty {
                        Text(followStore.isChecking ? "Checking for new chapters…" : "No new chapters. Pull down to check now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    } else {
                        SectionHeader(title: "New Chapters")
                            .headerRow()
                        ForEach(entries) { entry in
                            UpdateRow(entry: entry) {
                                // Opening it is seeing it.
                                followStore.markSeen(chapterID: entry.chapter.id, in: entry.follow)
                                router.open(entry.ref, using: sync)
                            }
                        }
                    }
                    SectionHeader(title: "Series")
                        .headerRow()
                    LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
                        ForEach(follows) { follow in
                            FollowedSeriesCell(follow: follow)
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 24, trailing: 0))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .toolbar {
                    if !entries.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Mark All as Seen", systemImage: "checkmark.circle") {
                                followStore.markAllSeen()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await followStore.checkForNewChapters(force: true)
        }
        // Follows change as checks run and chapters are seen.
        .task(id: follows.map { $0.key + String($0.unseenChapterIDs.count) }) {
            await load()
        }
    }

    private func load() async {
        var entries: [Entry] = []
        for follow in follows where !follow.unseenChapterIDs.isEmpty {
            // What the source listed last time, kept by the series screen
            // and the background check.
            guard let snapshot = await SeriesCache.read(server: follow.serverID, source: follow.sourceID, series: follow.seriesID) else { continue }
            let unseen = Set(follow.unseenChapterIDs)
            for known in snapshot.chapters where unseen.contains(known.chapter.id) {
                entries.append(Entry(follow: follow, chapter: known.chapter, published: known.chapter.publishedDate))
            }
        }
        // Newest first; chapters with no date sort by their place in the
        // series, after the dated ones.
        entries.sort { a, b in
            switch (a.published, b.published) {
            case (let x?, let y?): x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.chapter.id > b.chapter.id
            }
        }
        self.entries = .loaded(entries)
    }

}

private struct UpdateRow: View {
    let entry: UpdatesView.Entry
    let open: () -> Void
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                CoverView(source: servers.sourceImage(entry.follow.coverPath, on: entry.follow.serverID), title: entry.follow.title, cornerRadius: Metrics.rowCoverRadius)
                    .frame(width: Metrics.rowCoverWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.chapter.displayTitle)
                        .font(.body)
                        .lineLimit(2)
                    Text(entry.follow.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let published = entry.published {
                        Text(published, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if router.opening == entry.ref.ref {
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
