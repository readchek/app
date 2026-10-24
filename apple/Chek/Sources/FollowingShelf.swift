import SwiftData
import SwiftUI

/// The series you follow from sources, newest chapters first, each with
/// how many chapters you haven't seen.
struct FollowingShelf: View {
    @Query(sort: \FollowedSeries.followedAt, order: .reverse) private var follows: [FollowedSeries]
    @Environment(ServerStore.self) private var servers
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if !follows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Following") {
                    UpdatesView()
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.coverSpacing) {
                        // Series with something new come first.
                        ForEach(follows.sorted { $0.unseenChapterIDs.count > $1.unseenChapterIDs.count }) { follow in
                            FollowedSeriesCell(follow: follow)
                                .frame(width: Metrics.shelfCoverWidth(regular: sizeClass == .regular))
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }
}

private struct FollowedSeriesCell: View {
    let follow: FollowedSeries
    @Environment(ServerStore.self) private var servers
    @Environment(FollowStore.self) private var follows

    var body: some View {
        NavigationLink(value: Route.sourceSeries(follow.serverID, source: follow.sourceID, seriesID: follow.seriesID, title: follow.title)) {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(source: servers.sourceImage(follow.coverPath, on: follow.serverID), title: follow.title)
                    .overlay(alignment: .topTrailing) {
                        if !follow.unseenChapterIDs.isEmpty {
                            Text(follow.unseenChapterIDs.count, format: .number)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.tint, in: .capsule)
                                .padding(6)
                                .accessibilityLabel(Text("^[\(follow.unseenChapterIDs.count) new chapter](inflect: true)"))
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(follow.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(follow.unseenChapterIDs.isEmpty ? "^[\(follow.chapterCount) chapter](inflect: true)" : "^[\(follow.unseenChapterIDs.count) new chapter](inflect: true)")
                        .font(.caption2)
                        .foregroundStyle(follow.unseenChapterIDs.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
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
