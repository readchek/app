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
                SourceSeriesContent(account: account, source: source, content: content) {
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
            onLoad?(content.series)
        } catch {
            // A refresh that fails keeps what's already showing.
            if state.value == nil {
                state = .failed(DisplayError(error))
            }
        }
    }
}

private struct SourceSeriesContent: View {
    @State private var headerVisible = true
    let account: UUID
    let source: String
    let content: SourceSeriesModel.Content
    let refresh: () async -> Void
    @Query private var states: [SourceReadingState]
    @Environment(ServerStore.self) private var servers
    /// Long-running series are easier to read from their latest chapter.
    @AppStorage("sourceSeries.newestFirst") private var newestFirst = false

    init(account: UUID, source: String, content: SourceSeriesModel.Content, refresh: @escaping () async -> Void) {
        self.account = account
        self.source = source
        self.content = content
        self.refresh = refresh
        let seriesID = content.series.id
        _states = Query(filter: #Predicate<SourceReadingState> {
            $0.serverID == account && $0.sourceID == source && $0.seriesID == seriesID
        })
    }

    var body: some View {
        let statuses = Dictionary(states.map { ($0.chapterID, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            Section {
                SourceSeriesHeader(
                    series: content.series,
                    count: content.chapters.count,
                    cover: servers.sourceImage(content.series.coverUrl, on: account),
                    next: nextToRead(statuses: statuses).map { (chapterRef($0), statuses[$0.id]?.readingStatus ?? .new) }
                )
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
                    ForEach(newestFirst ? content.chapters.reversed() : content.chapters) { chapter in
                        SourceChapterRow(chapter: chapterRef(chapter), status: statuses[chapter.id]?.readingStatus ?? .new)
                    }
                }
            } header: {
                if content.chapters.count > 1 {
                    HStack {
                        Text("Chapters")
                        Spacer()
                        Button(newestFirst ? "Newest First" : "Oldest First", systemImage: "arrow.up.arrow.down") {
                            withAnimation(.snappy) { newestFirst.toggle() }
                        }
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                        .accessibilityHint(Text("Changes the order chapters are listed in."))
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
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
    @State private var isShowingFullSummary = false
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                CoverView(source: cover, title: series.title)
                    .frame(width: 96)
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
                Text(summary)
                    .font(.subheadline)
                    .lineLimit(isShowingFullSummary ? nil : 3)
                    .onTapGesture {
                        withAnimation(.snappy) { isShowingFullSummary.toggle() }
                    }
                    .accessibilityAddTraits(.isButton)
            }
            if let (chapter, status) = next {
                Button {
                    router.open(chapter, using: sync)
                } label: {
                    Text(status == .new ? "Start Reading" : "Continue \(chapter.chapterTitle)")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.vertical, 8)
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
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.open(chapter, using: sync)
        } label: {
            HStack(spacing: 12) {
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
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
