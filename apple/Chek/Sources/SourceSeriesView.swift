import SwiftData
import SwiftUI

/// A series from a source: its cover, summary and a button to read on from
/// where you are, then its chapters a page at a time, newest or oldest first.
struct SourceSeriesView: View {
    let account: UUID
    let source: String
    let seriesID: String
    let title: String
    @State private var isHeaderVisible = true
    @Environment(ServerStore.self) private var servers
    @Environment(ProgressStore.self) private var progress
    @State private var model: SourceSeriesModel?
    @State private var chapters: ChapterList?
    /// Long-running series are easier to read from their latest chapter.
    @AppStorage("sourceSeries.newestFirst") private var newestFirst = true

    var body: some View {
        Group {
            switch model?.state ?? .idle {
            case .loaded(let series):
                content(series)
            case .idle where chapters?.entries.isEmpty == false, .loading where chapters?.entries.isEmpty == false:
                // The chapters came first: they show under what's known of
                // the series, and the rest of it fills in when it arrives.
                content(ChekAPI.SourceSeries(id: seriesID, title: title, summary: nil, coverUrl: nil, contributors: [], readingDirection: nil))
            case .idle, .loading:
                LoadingState()
            case .failed(let error):
                FailureState(error: error) {
                    await model?.load()
                }
            }
        }
        // The header shows the title large, so the bar only takes it once
        // the header has scrolled away, as Music does for albums.
        .navigationTitle(isHeaderVisible ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .onPreferenceChange(SeriesHeaderVisibleKey.self) { visible in
            withAnimation(.easeInOut(duration: 0.2)) { isHeaderVisible = visible }
        }
        .onChange(of: chapters?.order) { _, order in
            // The order you last chose is the one the next series opens in.
            if let order {
                newestFirst = order == .newestFirst
            }
        }
        .task(id: seriesID) {
            let model = model ?? SourceSeriesModel(account: account, source: source, seriesID: seriesID, servers: servers)
            let chapters = chapters ?? ChapterList(server: account, source: source, seriesID: seriesID, order: newestFirst ? .newestFirst : .oldestFirst, servers: servers)
            let account = account
            let source = source
            model.onLoad = { [progress] series in
                progress.updateSourceSeries(series, server: account, source: source)
            }
            chapters.onPage = { [weak model] entries, total in
                guard let series = model?.state.value else { return }
                Task { await SeriesCache.merge(series, chapters: entries, total: total, server: account, source: source) }
            }
            self.model = model
            self.chapters = chapters
            // The series and its first page of chapters load side by side,
            // and so does chapter 1 when the list opens newest first, since
            // it's what Start Reading offers a new reader.
            async let series: Void = model.load()
            async let first = chapters.order == .newestFirst ? chapters.firstChapter() : nil
            await chapters.load()
            await series
            _ = await first
        }
    }
}

extension SourceSeriesView {
    private func content(_ series: ChekAPI.SourceSeries) -> some View {
        Group {
            if let chapters {
                SourceSeriesContent(account: account, source: source, series: series, chapters: chapters, staleError: model?.staleError) {
                    async let reloaded: Void = model?.load() ?? ()
                    await chapters.load(refresh: true)
                    await reloaded
                }
            }
        }
    }
}

/// Loads a source series' details. Its chapters are a ``ChapterList``.
@MainActor
@Observable
final class SourceSeriesModel {
    private(set) var state: LoadState<ChekAPI.SourceSeries> = .idle
    /// Why the last refresh failed while the series from before still shows.
    private(set) var staleError: DisplayError?
    private let account: UUID
    private let source: String
    private let seriesID: String
    private let servers: ServerStore
    /// Told about the series each time it loads, so places in its chapters
    /// can pick up its cover.
    @ObservationIgnored var onLoad: ((ChekAPI.SourceSeries) -> Void)?

    init(account: UUID, source: String, seriesID: String, servers: ServerStore) {
        self.account = account
        self.source = source
        self.seriesID = seriesID
        self.servers = servers
    }

    func load() async {
        // What was seen last time shows at once while the source answers,
        // since series change rarely and a source can take seconds.
        if state.value == nil, let snapshot = await SeriesCache.read(server: account, source: source, series: seriesID) {
            state = .loaded(snapshot.series)
        } else if state.value == nil {
            state = .loading
        }
        let source = source
        let seriesID = seriesID
        do {
            let series = try await servers.request(account) { client throws(ChekError) in
                try await client.series(seriesID, inSource: source)
            }
            state = .loaded(series)
            staleError = nil
            onLoad?(series)
            await SeriesCache.merge(series, chapters: [], total: nil, server: account, source: source)
        } catch {
            // A refresh that fails keeps what's already showing, and says so.
            if state.value == nil {
                state = .failed(DisplayError(error))
            } else {
                staleError = DisplayError(error)
            }
        }
    }
}

private struct SourceSeriesContent: View {
    @State private var headerVisible = true
    let account: UUID
    let source: String
    let series: ChekAPI.SourceSeries
    let chapters: ChapterList
    let staleError: DisplayError?
    let refresh: () async -> Void
    @Query private var states: [SourceReadingState]
    @Query private var follows: [FollowedSeries]
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(FollowStore.self) private var followStore
    @Environment(ProgressStore.self) private var progress
    @Environment(Downloads.self) private var downloads
    // Color.accentColor is the asset's color, not the theme's.
    @Environment(AppearanceSettings.self) private var appearance
    /// The chapter the header's button opens, worked out from your places.
    @State private var next: (chapter: SourceChapterRef, status: ReadingStatus)?

    init(account: UUID, source: String, series: ChekAPI.SourceSeries, chapters: ChapterList, staleError: DisplayError?, refresh: @escaping () async -> Void) {
        self.account = account
        self.source = source
        self.series = series
        self.chapters = chapters
        self.staleError = staleError
        self.refresh = refresh
        let seriesID = series.id
        _states = Query(filter: #Predicate<SourceReadingState> {
            $0.serverID == account && $0.sourceID == source && $0.seriesID == seriesID
        })
        let key = FollowedSeries.key(server: account, source: source, series: seriesID)
        _follows = Query(filter: #Predicate<FollowedSeries> { $0.key == key })
    }

    var body: some View {
        let statuses = Dictionary(states.map { ($0.chapterID, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            if let staleError {
                StaleNotice(error: staleError)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                SourceSeriesHeader(
                    series: series,
                    count: chapterCount,
                    cover: servers.sourceImage(series.coverUrl, on: account),
                    next: next,
                    isFollowing: !follows.isEmpty
                ) {
                    if let follow = follows.first {
                        followStore.unfollow(follow)
                    } else {
                        followStore.follow(series, count: chapters.total ?? 0, server: account, source: source)
                    }
                }
                .listRowSeparator(.hidden)
                .onScrollVisibilityChange(threshold: 0.2) { visible in
                    headerVisible = visible
                }
                .preference(key: SeriesHeaderVisibleKey.self, value: headerVisible)
            }
            // On the sections, not the row: the lines around the header
            // are the sections' own.
            .listSectionSeparator(.hidden)
            Section {
                switch chapters.phase {
                case .idle, .loading:
                    ForEach(0..<8, id: \.self) { _ in
                        PlaceholderChapterRow()
                    }
                case .failed(let failure):
                    // Under the header, not over it, so the series still reads.
                    FailureState(error: failure) {
                        await chapters.load()
                    }
                    .listRowSeparator(.hidden)
                case .loaded where chapters.entries.isEmpty, .loadingMore where chapters.entries.isEmpty:
                    EmptyState("This site doesn't have chapters for this series. Licensed series are often available only from their publisher.", systemImage: "books.vertical")
                    .listRowSeparator(.hidden)
                case .loaded, .loadingMore:
                    chapterRows(statuses: statuses)
                }
            } header: {
                if (chapters.total ?? 0) > 1 {
                    ChaptersHeader(chapters: chapters, series: series, account: account, source: source, statuses: statuses)
                }
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
        }
        .alert(
            downloads.failure?.title ?? "",
            isPresented: Binding { downloads.failure != nil } set: { if !$0 { downloads.failure = nil } }
        ) {
            Button("OK") {}
        } message: {
            if let message = downloads.failure?.message {
                Text(message)
            }
        }
        .task(id: chapters.total) {
            // Opening the series is seeing its chapters: none are new now.
            if let total = chapters.total {
                followStore.didOpen(server: account, source: source, series: series, count: total)
            }
        }
        .task(id: NextKey(states: states, first: chapters.first?.id)) {
            next = await nextToRead(statuses: statuses)
        }
    }

    @ViewBuilder
    private func chapterRows(statuses: [String: SourceReadingState]) -> some View {
        if chapters.hasMoreBefore {
            Button {
                Task { await chapters.loadEarlier() }
            } label: {
                Label(chapters.order == .newestFirst ? "Show Newer Chapters" : "Show Earlier Chapters", systemImage: "arrow.up")
            }
        }
        ForEach(chapters.entries) { entry in
            let ref = chapterRef(entry.chapter)
            // Read in any release, the chapter is read.
            let status = entry.chapter.allReleases.lazy.compactMap { statuses[$0.id]?.readingStatus }.first ?? .new
            let download = downloads.state(of: ref.ref)
            SourceChapterRow(
                chapter: ref,
                release: entry.chapter,
                status: status,
                isNew: follows.first?.unseenChapterIDs.contains(entry.chapter.id) == true,
                download: download,
                preferredGroup: chapters.preferredGroup,
                open: { release in router.open(chapterRef(entry.chapter.picking(release)), using: sync) },
                prefer: { group in Task { await chapters.prefer(group: group) } }
            )
                .contextMenu {
                    if SourceFormats.canDownload(source, on: account) {
                        DownloadAction(item: .chapter(ref), state: download)
                        Divider()
                    }
                    if status == .finished {
                        Button("Mark as Unread", systemImage: "circle") {
                            progress.markUnread(ref)
                        }
                    } else {
                        Button("Mark as Finished", systemImage: "checkmark.circle") {
                            progress.markRead(ref)
                        }
                    }
                    if entry.position > 1 {
                        Button("Mark Previous as Finished", systemImage: "text.badge.checkmark") {
                            Task { await markRead(before: entry.position) }
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if SourceFormats.canDownload(source, on: account) {
                        DownloadAction(item: .chapter(ref), state: download)
                            .tint(download == .downloaded ? .secondary : appearance.theme.tint)
                    }
                }
                .onAppear {
                    // The next page starts loading a little before the end.
                    if entry.id == chapters.entries.dropLast(10).last?.id || entry.id == chapters.entries.last?.id {
                        Task { await chapters.loadMore() }
                    }
                }
        }
        if chapters.phase == .loadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        } else if let failure = chapters.moreFailure {
            StaleNotice(error: failure)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    private func chapterRef(_ chapter: ChekAPI.SourceChapter) -> SourceChapterRef {
        SourceChapterRef(series: series, chapter: chapter, server: account, source: source)
    }

    /// How many chapters the series has, as distinct from its releases;
    /// 0 when that isn't known yet, as for a site that pages its list.
    private var chapterCount: Int {
        if let count = chapters.chapterCount {
            return count
        }
        // A server from before release groups lists one release a chapter.
        let grouped = chapters.entries.contains { $0.chapter.releases != nil }
        return grouped ? 0 : chapters.total ?? 0
    }

    /// Marks every chapter before `position` in reading order as finished.
    /// They may not be loaded, so they're asked for, a server page at a time.
    private func markRead(before position: Int) async {
        let seriesID = series.id
        let source = source
        guard let earlier = try? await servers.request(account, { client throws(ChekError) in
            try await client.chapters(ofSeries: seriesID, inSource: source, from: 0, to: position - 1)
        }) else { return }
        progress.markRead(earlier.map(chapterRef))
    }

    /// The chapter you opened last, or the one after it once it's
    /// finished, or else the first.
    private func nextToRead(statuses: [String: SourceReadingState]) async -> (chapter: SourceChapterRef, status: ReadingStatus)? {
        let latest = states.filter { $0.lastOpenedAt != nil }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
        if let latest {
            let ref = SourceChapterRef(latest)
            guard latest.readingStatus == .finished else { return (ref, latest.readingStatus) }
            if case .found(let following) = await sync.chapter(after: ref) {
                return (following, statuses[following.chapterID]?.readingStatus ?? .new)
            }
            return (ref, latest.readingStatus)
        }
        guard let first = await chapters.firstChapter() else { return nil }
        return (chapterRef(first), .new)
    }

    /// What the next chapter depends on: which chapter you opened last and
    /// whether it's finished.
    private struct NextKey: Hashable {
        var latest: String?
        var finished: Bool
        var first: String?

        init(states: [SourceReadingState], first: String?) {
            self.first = first
            let latest = states.filter { $0.lastOpenedAt != nil }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
            self.latest = latest?.chapterID
            finished = latest?.readingStatus == .finished
        }
    }
}

/// "Chapters", then the order, a jump to any run of chapters in a long
/// series, and downloads for the series.
private struct ChaptersHeader: View {
    let chapters: ChapterList
    let series: ChekAPI.SourceSeries
    let account: UUID
    let source: String
    let statuses: [String: SourceReadingState]

    var body: some View {
        HStack(spacing: 16) {
            Text("Chapters")
            Spacer()
            // A menu with the current order ticked, so the label reads as
            // what's shown rather than what a tap would do.
            Menu {
                Picker("Order", selection: Binding(
                    get: { chapters.order },
                    set: { order in Task { await chapters.setOrder(order) } }
                )) {
                    Text("Newest First").tag(ChapterList.Order.newestFirst)
                    Text("Oldest First").tag(ChapterList.Order.oldestFirst)
                }
                .pickerStyle(.inline)
                if !chapters.ranges.isEmpty {
                    // Long series in runs of a page, so any chapter is two
                    // taps away instead of a long scroll.
                    Menu("Go to Chapters", systemImage: "arrow.right.circle") {
                        ForEach(chapters.order == .newestFirst ? chapters.ranges.reversed() : chapters.ranges, id: \.self) { range in
                            Button("\(range.lowerBound)–\(range.upperBound)") {
                                Task { await chapters.jump(to: range) }
                            }
                        }
                    }
                }
            } label: {
                Label(chapters.order == .newestFirst ? "Newest First" : "Oldest First", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .font(.subheadline)
            if SourceFormats.canDownload(source, on: account) {
                SeriesDownloadsMenu(series: series, account: account, source: source, statuses: statuses)
            }
        }
        .textCase(nil)
    }
}

extension SourceChapterRef {
    init(series: ChekAPI.SourceSeries, chapter: ChekAPI.SourceChapter, server: UUID, source: String) {
        self.init(
            server: server,
            source: source,
            seriesID: series.id,
            seriesTitle: series.title,
            chapterID: chapter.id,
            chapterTitle: chapter.displayTitle,
            isRightToLeft: series.readingDirection == "rtl",
            seriesCoverPath: series.coverUrl
        )
    }
}

extension ChekAPI.SourceChapter {
    /// "Chapter 12" or "12 · The Title", from what the source gives.
    var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number, !number.isEmpty else {
            return title.isEmpty ? String(localized: "Chapter") : title
        }
        if title.isEmpty {
            return String(localized: "Chapter \(number)")
        }
        return title.localizedCaseInsensitiveContains(number) ? title : "\(number) · \(title)"
    }
}

/// The series' cover beside its title and authors, its summary, and the
/// button that picks up where you are.
struct SourceSeriesHeader: View {
    let series: ChekAPI.SourceSeries
    let count: Int
    let cover: CoverSource
    let next: (chapter: SourceChapterRef, status: ReadingStatus)?
    let isFollowing: Bool
    let toggleFollow: () -> Void
    @State private var isShowingFullSummary = false
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        let isRegular = sizeClass == .regular
        VStack(alignment: .leading, spacing: 16) {
            // Title beside the top of the cover, as Books and Music lay
            // out a title page.
            HStack(alignment: .top, spacing: 16) {
                CoverView(source: cover, title: series.title)
                    .frame(width: Metrics.headerCoverWidth(regular: isRegular))
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(3)
                    if !authors.isEmpty {
                        Text(authors)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let detail = Self.detail(count: count, status: series.status, year: series.year, rating: series.rating) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let tags = series.tags, !tags.isEmpty {
                // Genres as a row of pills, scrolling past the edge rather
                // than wrapping into a block that pushes the summary down.
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            if let summary = Self.summary(series.summary) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(isShowingFullSummary ? nil : 3)
                    // Whether three lines cut it off isn't known without
                    // measuring, so the control shows for any summary long
                    // enough that they might.
                    if Self.mayBeCutOff(summary) {
                        Text(isShowingFullSummary ? "Less" : "More")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.snappy) { isShowingFullSummary.toggle() }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(isShowingFullSummary ? "Shows less of the summary" : "Shows the whole summary"))
            }
            // Two buttons of one size, as Books pairs "Want to Read" and
            // "Read"; style, not width, says which one matters. One under
            // the other at text sizes where two across would squeeze the
            // reading one to nothing.
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if let (chapter, status) = next {
                    Button {
                        router.open(chapter, using: sync)
                    } label: {
                        Text(status == .new ? "Start Reading" : "Continue \(chapter.chapterTitle)")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                // Following keeps the series on Home, with its new
                // chapters counted, so you don't have to search again.
                Button {
                    toggleFollow()
                } label: {
                    Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isFollowing ? .secondary : appearance.theme.tint)
            }
            .buttonBorderShape(.capsule)
            .fixedSize(horizontal: false, vertical: true)
            // On a wide screen a button the width of the page is a bar,
            // not a button.
            .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    /// "97 chapters · Ongoing · 2018 · Suggestive", from whatever is known.
    static func detail(count: Int, status: String?, year: Int?, rating: ChekAPI.ContentRating? = nil) -> String? {
        var parts: [String] = []
        // Inflection markup only works in `Text`, so the plural is spelt out.
        if count == 1 {
            parts.append(String(localized: "1 chapter"))
        } else if count > 1 {
            parts.append(String(localized: "\(count) chapters"))
        }
        switch status {
        case "ongoing": parts.append(String(localized: "Ongoing"))
        case "completed": parts.append(String(localized: "Completed"))
        case "hiatus": parts.append(String(localized: "On Hiatus"))
        case "cancelled": parts.append(String(localized: "Canceled"))
        default: break
        }
        if let year {
            parts.append(String(year))
        }
        // Safe goes without saying; anything more is worth knowing.
        if let rating, rating != .safe {
            parts.append(String(localized: rating.title))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Whether `summary` might run past three lines at the summary's size.
    static func mayBeCutOff(_ summary: AttributedString) -> Bool {
        let text = String(summary.characters)
        return text.count > 160 || text.contains("\n")
    }

    /// The summary with its Markdown drawn as styling, as sources such as
    /// MangaDex write them. Sources often add credits and links after a
    /// rule, which aren't part of the story, so only what's before it shows.
    static func summary(_ text: String?) -> AttributedString? {
        guard var text = text?.replacingOccurrences(of: "\r\n", with: "\n") else { return nil }
        if let rule = text.range(of: "\n---") ?? text.range(of: "\n___") ?? text.range(of: "\n***") {
            text = String(text[..<rule.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sources sometimes end a cut-off summary with a line of dots.
        while text.hasSuffix("...") || text.hasSuffix("\u{2026}") {
            text = String(text.dropLast(text.hasSuffix("...") ? 3 : 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return nil }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        var summary = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        // Links would open a browser from a tap meant to expand the text.
        for run in summary.runs where run.link != nil {
            summary[run.range].link = nil
        }
        return summary
    }

    private var authors: String {
        var seen = Set<String>()
        return series.contributors.map(\.name).filter { seen.insert($0).inserted }.formatted(.list(type: .and))
    }
}

/// A chapter with how far you've read it, which opens it in the reader.
private struct SourceChapterRow: View {
    let chapter: SourceChapterRef
    /// The chapter as listed, with every release of it.
    let release: ChekAPI.SourceChapter
    let status: ReadingStatus
    var isNew = false
    var download = Downloads.State.none
    var preferredGroup: String?
    let open: (ChekAPI.SourceRelease) -> Void
    let prefer: (String?) -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 12) {
            Button {
                open(release.allReleases[0])
            } label: {
                HStack(spacing: 12) {
                    if isNew {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel(Text("New"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.chapterTitle)
                            .font(.body)
                            .foregroundStyle(status == .finished ? .secondary : .primary)
                            .lineLimit(2)
                        if let detail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if router.opening == chapter.ref {
                        ProgressView()
                    } else {
                        // Most chapters are unread, so only the others say so.
                        StatusText(status: status)
                    }
                    DownloadIndicator(state: download)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if release.allReleases.count > 1 {
                ReleasesMenu(chapter: release, preferredGroup: preferredGroup, open: open, prefer: prefer)
            }
        }
    }

    /// When it came out, as Podcasts dates episodes, and who released it.
    private var detail: String? {
        let date = release.publishedDate?.formatted(.dateTime.day().month(.abbreviated).year())
        let parts = [date, release.releaseGroup].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A chapter's other releases, one per group that put it out: read another
/// one, or always show one group's for this series.
private struct ReleasesMenu: View {
    let chapter: ChekAPI.SourceChapter
    let preferredGroup: String?
    let open: (ChekAPI.SourceRelease) -> Void
    let prefer: (String?) -> Void

    var body: some View {
        Menu {
            Section("Read") {
                ForEach(chapter.allReleases) { release in
                    Button {
                        open(release)
                    } label: {
                        Text(release.releaseGroup ?? String(localized: "Unknown Group"))
                        if let subtitle = subtitle(of: release) {
                            Text(subtitle)
                        }
                    }
                }
            }
            // Whose release every chapter of the series shows, ticked, with
            // the default pick (official, else newest) as the first choice.
            Picker("Always Show", selection: Binding(
                get: { preferredGroup.map { group in groups.first { $0.localizedCaseInsensitiveCompare(group) == .orderedSame } ?? group } },
                set: { prefer($0) }
            )) {
                Text("Default Release").tag(String?.none)
                ForEach(groups, id: \.self) { group in
                    Text(group).tag(String?.some(group))
                }
            }
            .pickerStyle(.menu)
        } label: {
            Text("^[\(chapter.allReleases.count) release](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.fill.quaternary, in: .capsule)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Releases"))
    }

    /// The groups that released the chapter, each once.
    private var groups: [String] {
        var seen = Set<String>()
        return chapter.allReleases.compactMap(\.releaseGroup).filter { seen.insert($0.lowercased()).inserted }
    }

    /// "Official · 12 Oct 2026", from what's known.
    private func subtitle(of release: ChekAPI.SourceRelease) -> String? {
        var parts: [String] = []
        if release.official == true {
            parts.append(String(localized: "Official"))
        }
        if let date = release.publishedDate {
            parts.append(date.formatted(.dateTime.day().month(.abbreviated).year()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Downloads for the whole series at once, from the chapters header. The
/// chapters it needs may not be loaded, so it asks for them when chosen.
private struct SeriesDownloadsMenu: View {
    let series: ChekAPI.SourceSeries
    let account: UUID
    let source: String
    let statuses: [String: SourceReadingState]
    @Environment(Downloads.self) private var downloads
    @Environment(ServerStore.self) private var servers
    @State private var pendingAll: [SourceChapterRef] = []
    @State private var isFinding = false

    var body: some View {
        let kept = downloads.chapters(on: account, source: source, series: series.id)
        Menu("Downloads", systemImage: "arrow.down.circle") {
            Section("Download") {
                Button("Next 5 Unread", systemImage: "arrow.down.circle") {
                    Task { await download(limit: 5) }
                }
                Button("All Unread", systemImage: "arrow.down.circle.fill") {
                    Task { await download(limit: nil) }
                }
            }
            .disabled(isFinding)
            if !kept.isEmpty {
                Divider()
                Button("Remove ^[\(kept.count) Download](inflect: true)", systemImage: "trash", role: .destructive) {
                    downloads.remove(kept.map(Downloads.Item.chapter))
                }
            }
        }
        .font(.subheadline)
        .labelStyle(.iconOnly)
        .confirmationDialog(
            "Download ^[\(pendingAll.count) Chapter](inflect: true)?",
            isPresented: Binding { !pendingAll.isEmpty } set: { if !$0 { pendingAll = [] } },
            titleVisibility: .visible
        ) {
            Button("Download All") {
                downloads.download(pendingAll.map(Downloads.Item.chapter))
                pendingAll = []
            }
        } message: {
            Text("They download one at a time while Chek is open and stay on this device until you remove them.")
        }
    }

    /// Unread chapters not yet downloaded, in reading order, after the last
    /// one you opened; the first `limit` of them, or all of them once you
    /// confirm a long series' count.
    private func download(limit: Int?) async {
        isFinding = true
        defer { isFinding = false }
        let seriesID = series.id
        let source = source
        let lastOpened = statuses.values.filter { $0.lastOpenedAt != nil }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }?.chapterID
        // The next few need only a page after where you are; all of them
        // need the rest of the series.
        guard let candidates = try? await servers.request(account, { client throws(ChekError) in
            if limit != nil {
                return try await client.chapterPage(ofSeries: seriesID, inSource: source, order: .oldestFirst, after: lastOpened, limit: 50).items
            }
            let all = try await client.chapters(ofSeries: seriesID, inSource: source)
            guard let lastOpened, let index = all.firstIndex(where: { $0.id == lastOpened }) else { return all }
            return Array(all[all.index(after: index)...])
        }) else { return }
        let pending = candidates
            .filter { statuses[$0.id]?.readingStatus != .finished }
            .map { SourceChapterRef(series: series, chapter: $0, server: account, source: source) }
            .filter { downloads.state(of: $0.ref) == .none }
        if let limit {
            downloads.download(pending.prefix(limit).map(Downloads.Item.chapter))
        } else if pending.count > 10 {
            // A long series is a lot of space and a lot of requests to the
            // source's site, so the count is put to you first.
            pendingAll = pending
        } else {
            downloads.download(pending.map(Downloads.Item.chapter))
        }
    }
}
