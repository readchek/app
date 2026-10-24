import SwiftData
import SwiftUI

/// The series you follow from sources, newest chapters first, each with
/// how many chapters you haven't seen. A row of Reading Now's list.
struct FollowingShelf: View {
    @Query(sort: \FollowedSeries.followedAt, order: .reverse) private var follows: [FollowedSeries]

    var body: some View {
        if !follows.isEmpty {
            CoverShelf(title: "Following", route: .updates) {
                // Series with something new come first.
                ForEach(follows.sorted { $0.unseenChapterIDs.count > $1.unseenChapterIDs.count }) { follow in
                    FollowedSeriesCell(follow: follow)
                        .shelfCell()
                }
            }
            .shelfRow()
        }
    }
}

private struct FollowedSeriesCell: View {
    let follow: FollowedSeries
    @Environment(ServerStore.self) private var servers
    @Environment(FollowStore.self) private var follows

    var body: some View {
        let unseen = follow.unseenChapterIDs.count
        NavigationLink(value: Route.sourceSeries(follow.serverID, source: follow.sourceID, seriesID: follow.seriesID, title: follow.title)) {
            VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
                CoverView(source: servers.sourceImage(follow.coverPath, on: follow.serverID), title: follow.title)
                    .overlay(alignment: .topTrailing) {
                        if unseen > 0 {
                            Text(unseen, format: .number)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.tint, in: .capsule)
                                .padding(6)
                                .accessibilityLabel(Text("^[\(unseen) new chapter](inflect: true)"))
                        }
                    }
                CoverCaption(
                    title: follow.title,
                    detail: Text(unseen == 0 ? "^[\(follow.chapterCount) chapter](inflect: true)" : "^[\(unseen) new chapter](inflect: true)"),
                    isDetailHighlighted: unseen > 0
                )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Not destructive: nothing is lost, and the series is a search away.
            Button("Unfollow", systemImage: "minus.circle") {
                follows.unfollow(follow)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
