import SwiftUI

/// On the last page, the way on: the next chapter or volume as one big
/// button, looked up while you read so it's there the moment you arrive,
/// as Mihon's and Webtoon's are. Finishing one never means leaving the
/// reader to find the next. At the end of a series it says you're caught
/// up and offers to follow it for new chapters.
struct ChapterEndCard: View {
    let session: ReaderSession
    /// What's being got ready to open, if anything.
    let opening: ReadingTarget?
    let open: (ReadingTarget) -> Void
    /// Asks again what comes next, after the server couldn't be reached.
    let retry: () -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack {
            Spacer()
            if isShowing {
                content
                    .frame(maxWidth: 440)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Metrics.margin)
        // Clear of the scrubber when the controls are showing.
        .padding(.bottom, session.isShowingControls ? 64 : 16)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: isShowing)
        .animation(.snappy, value: session.next)
        .animation(.snappy, value: session.isShowingControls)
    }

    private var isShowing: Bool {
        session.controller.state == .ready && session.isOnLastPage
    }

    @ViewBuilder private var content: some View {
        switch session.next {
        case .found(let target):
            NextButton(target: target, isOpening: opening == target) {
                open(target)
            }
        case .looking:
            Label {
                session.item.sourceChapter == nil ? Text("Finding What's Next") : Text("Finding the Next Chapter")
            } icon: {
                ProgressView()
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .readerCardGlass(kind: session.item.kind, in: .capsule)
        case .unknown:
            // Offline, most likely: not the end, just not known.
            HStack(spacing: 12) {
                Button(action: retry) {
                    Label {
                        session.item.sourceChapter == nil ? Text("Check Again") : Text("Check for Next Chapter")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                doneButton
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(10)
            .readerCardGlass(kind: session.item.kind, in: .capsule)
        case .end:
            CaughtUp(item: session.item) {
                router.closeReader()
            }
        case .none:
            // The one thing left to do, so it stands out from the page.
            doneButton
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }

    private var doneButton: some View {
        Button {
            router.closeReader()
        } label: {
            Label("Done", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }
}

/// The next chapter, volume or book, named, as the one obvious thing to
/// tap.
private struct NextButton: View {
    let target: ReadingTarget
    let isOpening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    label
                        .font(.caption.weight(.semibold))
                        .opacity(0.8)
                    Text(target.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isOpening {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.forward")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(isOpening)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(target.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var label: Text {
        target.isChapter ? Text("Next Chapter") : Text("Next in Series")
    }
}

/// At the last of a series: that you're caught up, and for a series from
/// a site, a way to hear when the next chapter comes out.
private struct CaughtUp: View {
    let item: ReadingItem
    let done: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                (item.sourceChapter == nil ? Text("That's the Last One") : Text("You're All Caught Up"))
                    .font(.headline)
                if let series = item.series {
                    (item.sourceChapter == nil ? Text("You've reached the end of \(series).") : Text("That's the latest chapter of \(series)."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 12) {
                if let chapter = item.sourceChapter {
                    FollowSeriesButton(chapter: chapter)
                }
                Button(action: done) {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .readerCardGlass(kind: item.kind, in: .rect(cornerRadius: 28))
    }
}

/// Follows a source series from the reader, so a new chapter shows on
/// Updates and as a notification rather than needing to be checked for.
private struct FollowSeriesButton: View {
    let chapter: SourceChapterRef
    @Environment(FollowStore.self) private var follows
    @Environment(ServerStore.self) private var servers
    /// The series and how many chapters it has, which following needs.
    @State private var series: (series: ChekAPI.SourceSeries, count: Int)?
    @State private var isFollowing = false

    var body: some View {
        Group {
            if isFollowing {
                Label("Following", systemImage: "bell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            } else if let series {
                Button {
                    follows.follow(series.series, count: series.count, server: chapter.server, source: chapter.source)
                    isFollowing = true
                } label: {
                    Label("Follow", systemImage: "bell")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .accessibilityHint(Text("Get notified when a new chapter comes out."))
            }
        }
        .task(id: chapter.seriesID) {
            isFollowing = follows.followed(server: chapter.server, source: chapter.source, series: chapter.seriesID) != nil
            if !isFollowing {
                series = await lookUpSeries()
            }
        }
    }
}

extension FollowSeriesButton {
    /// The series from what's kept of it, or from its source when nothing
    /// is, as when the chapter was opened from Home rather than the series.
    private func lookUpSeries() async -> (series: ChekAPI.SourceSeries, count: Int)? {
        if let kept = await SeriesCache.read(server: chapter.server, source: chapter.source, series: chapter.seriesID), let total = kept.total {
            return (kept.series, total)
        }
        let seriesID = chapter.seriesID
        let source = chapter.source
        guard let series = try? await servers.request(chapter.server, { client throws(ChekError) in
            try await client.series(seriesID, inSource: source)
        }), let page = try? await servers.request(chapter.server, { client throws(ChekError) in
            try await client.chapterPage(ofSeries: seriesID, inSource: source, order: .newestFirst, limit: 1)
        }) else { return nil }
        return (series, page.total)
    }
}

extension View {
    /// Glass for the cards over the last page, tinted toward the reader's
    /// own colors. Plain glass takes on the page under it, which over a
    /// white page is a grey that nothing on it reads against.
    fileprivate func readerCardGlass(kind: PublicationKind, in shape: some Shape) -> some View {
        modifier(ReaderCardGlass(kind: kind, shape: shape))
    }
}

private struct ReaderCardGlass<CardShape: Shape>: ViewModifier {
    let kind: PublicationKind
    let shape: CardShape
    @Environment(ReaderSettings.self) private var settings

    func body(content: Content) -> some View {
        content.glassEffect(.regular.tint(tint), in: shape)
    }

    private var tint: Color {
        switch kind {
        // Comics always read in dark mode, whatever the page's colors.
        case .comic: .black.opacity(0.6)
        case .book: ReaderTheme(settings.theme).background.opacity(0.85)
        }
    }
}
