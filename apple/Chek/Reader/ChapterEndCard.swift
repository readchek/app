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
    /// Whether it's been pulled down out of the way, as for reading the
    /// last lines of a book under it. It comes back on the next visit to
    /// the last page.
    @State private var isPutAway = false
    /// How far it's being pulled down.
    @State private var pull: CGFloat = 0

    var body: some View {
        VStack {
            Spacer()
            if isShowing && !isPutAway {
                VStack(spacing: 6) {
                    // Says it can be pulled down, as a sheet's does.
                    Capsule()
                        .fill(.white.opacity(0.7))
                        .frame(width: 36, height: 5)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .accessibilityHidden(true)
                    content
                }
                .frame(maxWidth: 440)
                .offset(y: pull)
                .gesture(putAway)
                .accessibilityAction(named: Text("Hide")) { isPutAway = true }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Metrics.margin)
        // Clear of the scrubber when the controls are showing.
        .padding(.bottom, session.isShowingControls ? 64 : 16)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: isShowing)
        .onChange(of: isShowing) { _, showing in
            if !showing {
                isPutAway = false
            }
        }
        .animation(.snappy, value: session.next)
        .animation(.snappy, value: session.isShowingControls)
    }

    private var isShowing: Bool {
        session.controller.state == .ready && session.isOnLastPage
    }

    private var putAway: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Down follows the finger; up resists.
                let distance = value.translation.height
                pull = distance > 0 ? distance : distance / 6
            }
            .onEnded { value in
                withAnimation(.snappy) {
                    if value.translation.height > 50 || value.predictedEndTranslation.height > 140 {
                        isPutAway = true
                    }
                    pull = 0
                }
            }
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

/// At the last of a series: that you're caught up, and for a site
/// series that's still going, a way to hear when the next chapter comes
/// out. A finished series, or a book a site offers whole, just ends.
private struct CaughtUp: View {
    let item: ReadingItem
    let done: () -> Void
    @Environment(FollowStore.self) private var follows
    @Environment(ServerStore.self) private var servers
    /// The site series and how many chapters it has, once looked up.
    @State private var series: SeriesLookup?
    @State private var isFollowing = false
    @State private var isLookingUp = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                (isOngoing ? Text("You're All Caught Up") : Text("That's the Last One"))
                    .font(.headline)
                if let title = item.series {
                    (isOngoing ? Text("That's the latest chapter of \(title).") : Text("You've reached the end of \(title)."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 12) {
                if isOngoing {
                    followButton
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
        .animation(.snappy, value: isOngoing)
        .task(id: item.id) {
            guard let chapter = item.sourceChapter else { return }
            isFollowing = follows.followed(server: chapter.server, source: chapter.source, series: chapter.seriesID) != nil
            series = await SeriesLookup.find(chapter, servers: servers)
        }
    }

    /// Whether more may come. A site series is, unless the site says it's
    /// finished or it's a single book, such as a novel from a library of
    /// classics; until it's known, a book from a site is taken as whole.
    private var isOngoing: Bool {
        guard item.sourceChapter != nil else { return false }
        guard let series else { return item.kind == .comic }
        return series.isOngoing
    }

    @ViewBuilder private var followButton: some View {
        if isFollowing {
            Label("Following", systemImage: "bell.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        } else {
            Button {
                follow()
            } label: {
                Label {
                    Text("Follow")
                } icon: {
                    if isLookingUp {
                        ProgressView()
                    } else {
                        Image(systemName: "bell")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .disabled(isLookingUp)
            .accessibilityHint(Text("Get notified when a new chapter comes out."))
        }
    }

    /// Follows the series, looking it up again first if that failed, as
    /// when the site didn't answer the first time.
    private func follow() {
        guard let chapter = item.sourceChapter else { return }
        Task {
            if series == nil {
                isLookingUp = true
                series = await SeriesLookup.find(chapter, servers: servers)
                isLookingUp = false
            }
            guard let series else { return }
            follows.follow(series.series, count: series.count, server: chapter.server, source: chapter.source)
            isFollowing = true
        }
    }
}

/// What following a site series needs, and whether it's still going.
private struct SeriesLookup {
    let series: ChekAPI.SourceSeries
    /// How many releases it lists, which following counts new ones from.
    let count: Int

    var isOngoing: Bool {
        if series.status == "completed" || series.status == "cancelled" {
            return false
        }
        return count > 1
    }

    /// From what's kept of the series, or from its site when nothing is,
    /// as when the chapter was opened from Home rather than the series.
    static func find(_ chapter: SourceChapterRef, servers: ServerStore) async -> SeriesLookup? {
        if let kept = await SeriesCache.read(server: chapter.server, source: chapter.source, series: chapter.seriesID), let total = kept.total {
            return SeriesLookup(series: kept.series, count: total)
        }
        let seriesID = chapter.seriesID
        let source = chapter.source
        do {
            let series = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.series(seriesID, inSource: source)
            }
            let page = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.chapterPage(ofSeries: seriesID, inSource: source, order: .oldestFirst, limit: 1)
            }
            return SeriesLookup(series: series, count: page.total)
        } catch {
            return nil
        }
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
        // A dark page gets a lighter card, or the two run together.
        case .book where settings.theme == .dark: Color(white: 0.22).opacity(0.9)
        case .book: ReaderTheme(settings.theme).background.opacity(0.85)
        }
    }
}
