import SwiftData
import SwiftUI

/// A series from a source: its cover, summary and a button to read on from
/// where you are, then its chapters in reading order, as the server lists them.
struct SourceSeriesView: View {
    let account: UUID
    let source: String
    let seriesID: String
    let title: String
    @State private var isHeaderVisible = true
    @Environment(ServerStore.self) private var servers
    @Environment(ProgressStore.self) private var progress
    @State private var model: SourceSeriesModel?

    var body: some View {
        Group {
            switch model?.state ?? .idle {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "wifi.exclamationmark")
                } description: {
                    if let message = error.message {
                        Text(message)
                    }
                } actions: {
                    Button("Try Again") {
                        Task { await model?.load() }
                    }
                    .buttonStyle(.bordered)
                }
            case .loaded(let content):
                SourceSeriesContent(account: account, source: source, content: content, staleError: model?.staleError) {
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
        .task(id: seriesID) {
            let model = model ?? SourceSeriesModel(account: account, source: source, seriesID: seriesID, servers: servers)
            let account = account
            let source = source
            model.onLoad = { [progress] series in
                progress.updateSourceSeries(series, server: account, source: source)
            }
            self.model = model
            await model.load()
        }
    }
}

/// Loads a source series and its chapters together, so the screen shows
/// once with both.
@MainActor
@Observable
final class SourceSeriesModel {
    struct Content: Equatable {
        var series: ChekAPI.SourceSeries
        var chapters: [ChekAPI.SourceChapter]
        /// Why the chapters couldn't be listed, while the series could:
        /// the series still shows, with a way to try the chapters again.
        var chaptersFailure: DisplayError?
    }

    private(set) var state: LoadState<Content> = .idle
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

    nonisolated private static func chapters(of series: String, in source: String, client: ChekClient) async -> Result<[ChekAPI.SourceChapter], ChekError> {
        do {
            return .success(try await client.chapters(ofSeries: series, inSource: source))
        } catch {
            return .failure(error)
        }
    }

    func load() async {
        if state.value == nil {
            state = .loading
        }
        let source = source
        let seriesID = seriesID
        do {
            let content: Content = try await servers.request(account) { client throws(ChekError) in
                // `async let` loses the error type, so it's restored for the
                // store to see sign-outs.
                do {
                    async let series = client.series(seriesID, inSource: source)
                    async let chapters = Self.chapters(of: seriesID, in: source, client: client)
                    let listed = await chapters
                    let loaded = try await series
                    switch listed {
                    case .success(let chapters):
                        return Content(series: loaded, chapters: chapters, chaptersFailure: nil)
                    case .failure(.unauthorized):
                        // A session that ended is the store's to notice.
                        throw ChekError.unauthorized
                    case .failure(let error):
                        return Content(series: loaded, chapters: [], chaptersFailure: DisplayError(error))
                    }
                } catch let error as ChekError {
                    throw error
                } catch {
                    throw .invalidResponse
                }
            }
            state = .loaded(content)
            staleError = nil
            onLoad?(content.series)
            if content.chaptersFailure == nil {
                await SeriesCache.write(content.series, chapters: content.chapters, server: account, source: source)
            }
        } catch {
            // A refresh that fails keeps what's already showing, and says
            // so; with nothing showing yet, what the source said last time
            // stands in, so downloaded chapters can be read offline.
            if state.value == nil, let snapshot = await SeriesCache.read(server: account, source: source, series: seriesID) {
                state = .loaded(Content(series: snapshot.series, chapters: snapshot.chapters, chaptersFailure: nil))
                staleError = DisplayError(error)
            } else if state.value == nil {
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
    let content: SourceSeriesModel.Content
    let staleError: DisplayError?
    let refresh: () async -> Void
    @Query private var states: [SourceReadingState]
    @Query private var follows: [FollowedSeries]
    @Environment(ServerStore.self) private var servers
    @Environment(FollowStore.self) private var followStore
    @Environment(ProgressStore.self) private var progress
    @Environment(ChapterDownloads.self) private var downloads
    /// Long-running series are easier to read from their latest chapter.
    @AppStorage("sourceSeries.newestFirst") private var newestFirst = false

    init(account: UUID, source: String, content: SourceSeriesModel.Content, staleError: DisplayError?, refresh: @escaping () async -> Void) {
        self.account = account
        self.source = source
        self.content = content
        self.staleError = staleError
        self.refresh = refresh
        let seriesID = content.series.id
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
                    series: content.series,
                    count: content.chapters.count,
                    cover: servers.sourceImage(content.series.coverUrl, on: account),
                    next: nextToRead(statuses: statuses).map { (chapterRef($0), statuses[$0.id]?.readingStatus ?? .new) },
                    isFollowing: !follows.isEmpty
                ) {
                    if let follow = follows.first {
                        followStore.unfollow(follow)
                    } else {
                        followStore.follow(content.series, chapters: content.chapters, server: account, source: source)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .onScrollVisibilityChange(threshold: 0.2) { visible in
                    headerVisible = visible
                }
                .preference(key: SeriesHeaderVisibleKey.self, value: headerVisible)
            }
            Section {
                if let failure = content.chaptersFailure {
                    // Under the header, not over it, so the series still reads.
                    ContentUnavailableView {
                        Label(failure.title, systemImage: "wifi.exclamationmark")
                    } description: {
                        if let message = failure.message {
                            Text(message)
                        }
                    } actions: {
                        Button("Try Again") {
                            Task { await refresh() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .listRowSeparator(.hidden)
                } else if content.chapters.isEmpty {
                    ContentUnavailableView(
                        "No Chapters to Read",
                        systemImage: "books.vertical",
                        description: Text("This source has no chapters it can show for this series. Licensed series are often only on the publisher's own site.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    let ordered = newestFirst ? content.chapters.reversed() : content.chapters
                    ForEach(ordered) { chapter in
                        let ref = chapterRef(chapter)
                        let status = statuses[chapter.id]?.readingStatus ?? .new
                        let download = downloads.state(of: ref)
                        SourceChapterRow(chapter: ref, status: status, isNew: follows.first?.unseenChapterIDs.contains(chapter.id) == true, download: download)
                            .contextMenu {
                                DownloadAction(chapter: ref, state: download)
                                Divider()
                                if status == .finished {
                                    Button("Mark as Unread", systemImage: "circle") {
                                        progress.markUnread(ref)
                                    }
                                } else {
                                    Button("Mark as Read", systemImage: "checkmark.circle") {
                                        progress.markRead(ref)
                                    }
                                }
                                if let index = content.chapters.firstIndex(of: chapter), index > 0 {
                                    Button("Mark Previous as Read", systemImage: "checkmark.circle.badge.questionmark") {
                                        progress.markRead(content.chapters[..<index].map(chapterRef))
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                DownloadAction(chapter: ref, state: download)
                                    .tint(download == .downloaded ? .secondary : .accentColor)
                            }
                    }
                }
            } header: {
                if content.chapters.count > 1 {
                    HStack(spacing: 16) {
                        Text("Chapters")
                        Spacer()
                        Button(newestFirst ? "Newest First" : "Oldest First", systemImage: "arrow.up.arrow.down") {
                            withAnimation(.snappy) { newestFirst.toggle() }
                        }
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                        .accessibilityHint(Text("Changes the order chapters are listed in."))
                        SeriesDownloadsMenu(chapters: content.chapters.map(chapterRef), unread: unreadChapters(statuses: statuses).map(chapterRef))
                    }
                    .textCase(nil)
                }
            }
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
        .task(id: content.chapters.count) {
            // Opening the series is seeing its chapters: none are new now.
            followStore.didOpen(server: account, source: source, series: content.series, chapters: content.chapters)
        }
    }

    private func chapterRef(_ chapter: ChekAPI.SourceChapter) -> SourceChapterRef {
        SourceChapterRef(
            server: account,
            source: source,
            seriesID: content.series.id,
            seriesTitle: content.series.title,
            chapterID: chapter.id,
            chapterTitle: chapter.displayTitle,
            isRightToLeft: content.series.readingDirection == "rtl",
            seriesCoverPath: content.series.coverUrl
        )
    }

    /// The chapter you opened last, or the one after it once it's
    /// finished, or else the first.
    /// Chapters not yet finished, in reading order.
    private func unreadChapters(statuses: [String: SourceReadingState]) -> [ChekAPI.SourceChapter] {
        content.chapters.filter { statuses[$0.id]?.readingStatus != .finished }
    }

    private func nextToRead(statuses: [String: SourceReadingState]) -> ChekAPI.SourceChapter? {
        let inOrder = content.chapters
        let opened = inOrder.filter { statuses[$0.id]?.lastOpenedAt != nil }
        if let latest = opened.max(by: { (statuses[$0.id]?.lastOpenedAt ?? .distantPast) < (statuses[$1.id]?.lastOpenedAt ?? .distantPast) }) {
            guard statuses[latest.id]?.readingStatus == .finished else { return latest }
            if let index = inOrder.firstIndex(of: latest), inOrder.indices.contains(index + 1) {
                return inOrder[index + 1]
            }
            return latest
        }
        return inOrder.first
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
private struct SourceSeriesHeader: View {
    let series: ChekAPI.SourceSeries
    let count: Int
    let cover: CoverSource
    let next: (SourceChapterRef, ReadingStatus)?
    let isFollowing: Bool
    let toggleFollow: () -> Void
    @State private var isShowingFullSummary = false
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let isRegular = sizeClass == .regular
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                CoverView(source: cover, title: series.title)
                    .frame(width: isRegular ? 128 : 96)
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
                    if count > 0 {
                        Text("^[\(count) chapter](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
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
            }
            HStack(spacing: 10) {
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
                // Following keeps the series on Reading Now, with its new
                // chapters counted, so you don't have to search again.
                Button {
                    toggleFollow()
                } label: {
                    Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .tint(isFollowing ? .secondary : .accentColor)
            }
            .controlSize(.large)
            .fixedSize(horizontal: false, vertical: true)
            // On a wide screen a button the width of the page is a bar,
            // not a button.
            .frame(maxWidth: isRegular ? 440 : .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
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
    let status: ReadingStatus
    var isNew = false
    var download = ChapterDownloads.State.none
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.open(chapter, using: sync)
        } label: {
            HStack(spacing: 12) {
                if isNew {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(Text("New"))
                }
                Text(chapter.chapterTitle)
                    .font(.body)
                    .foregroundStyle(status == .finished ? .secondary : .primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if router.opening == chapter.ref {
                    ProgressView()
                } else if status != .new {
                    // Most chapters are unread, so only the others say so.
                    StatusText(status: status, fallback: nil)
                }
                DownloadIndicator(state: download)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A quiet mark of a chapter on the device, or on its way there.
private struct DownloadIndicator: View {
    let state: ChapterDownloads.State

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .waiting:
            Image(systemName: "arrow.down.circle.dotted")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Waiting to download"))
        case .downloading(let fraction):
            // iOS draws a determinate circular progress as a spinner, so
            // the ring is drawn here.
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(fraction, 0.02))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(.linear(duration: 0.2), value: fraction)
            .accessibilityLabel(Text("Downloading"))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Downloaded"))
        }
    }
}

/// The one download action that fits the chapter's state.
private struct DownloadAction: View {
    let chapter: SourceChapterRef
    let state: ChapterDownloads.State
    @Environment(ChapterDownloads.self) private var downloads

    var body: some View {
        switch state {
        case .none:
            Button("Download", systemImage: "arrow.down.circle") {
                downloads.download([chapter])
            }
        case .waiting, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") {
                downloads.cancel(chapter)
            }
        case .downloaded:
            Button("Remove Download", systemImage: "trash") {
                downloads.remove(chapter)
            }
        }
    }
}

/// Downloads for the whole series at once, from the chapters header.
private struct SeriesDownloadsMenu: View {
    let chapters: [SourceChapterRef]
    let unread: [SourceChapterRef]
    @Environment(ChapterDownloads.self) private var downloads
    @State private var isConfirmingAll = false

    var body: some View {
        let kept = chapters.filter(downloads.isDownloaded)
        let pending = unread.filter { downloads.state(of: $0) == .none }
        Menu("Downloads", systemImage: "arrow.down.circle") {
            Section("Download") {
                Button("Next \(min(pending.count, 5)) Unread", systemImage: "arrow.down.circle") {
                    downloads.download(Array(pending.prefix(5)))
                }
                .disabled(pending.isEmpty)
                Button("All Unread", systemImage: "arrow.down.circle.fill") {
                    // A long series is a lot of space and a lot of requests
                    // to the source's site, so the count is put to you first.
                    if pending.count > 10 {
                        isConfirmingAll = true
                    } else {
                        downloads.download(pending)
                    }
                }
                .disabled(pending.count < 2)
            }
            if !kept.isEmpty {
                Divider()
                Button("Remove ^[\(kept.count) Download](inflect: true)", systemImage: "trash", role: .destructive) {
                    downloads.remove(kept)
                }
            }
        }
        .font(.subheadline)
        .labelStyle(.iconOnly)
        .confirmationDialog("Download ^[\(pending.count) Chapter](inflect: true)?", isPresented: $isConfirmingAll, titleVisibility: .visible) {
            Button("Download All") {
                downloads.download(pending)
            }
        } message: {
            Text("They download one after another while Chek is open, and stay on this device until you remove them.")
        }
    }
}
