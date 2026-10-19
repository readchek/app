import SwiftData
import SwiftUI

/// A series from a source: its cover, summary and a button to read on from
/// where you are, then its chapters, newest first as sources list them.
struct SourceSeriesView: View {
    let account: UUID
    let source: String
    let seriesID: String
    let title: String
    @Environment(ServerStore.self) private var servers
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: seriesID) {
            let model = model ?? SourceSeriesModel(account: account, source: source, seriesID: seriesID, servers: servers)
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
    }

    private(set) var state: LoadState<Content> = .idle
    private let account: UUID
    private let source: String
    private let seriesID: String
    private let servers: ServerStore

    init(account: UUID, source: String, seriesID: String, servers: ServerStore) {
        self.account = account
        self.source = source
        self.seriesID = seriesID
        self.servers = servers
    }

    func load() async {
        if state.value == nil {
            state = .loading
        }
        let source = source
        let seriesID = seriesID
        do {
            let content = try await servers.request(account) { client throws(ChekError) in
                // `async let` loses the error type, so it's restored for the
                // store to see sign-outs.
                do {
                    async let series = client.series(seriesID, inSource: source)
                    async let chapters = client.chapters(ofSeries: seriesID, inSource: source)
                    return try await Content(series: series, chapters: chapters)
                } catch let error as ChekError {
                    throw error
                } catch {
                    throw .invalidResponse
                }
            }
            state = .loaded(content)
        } catch {
            // A refresh that fails keeps what's already showing.
            if state.value == nil {
                state = .failed(DisplayError(error))
            }
        }
    }
}

private struct SourceSeriesContent: View {
    let account: UUID
    let source: String
    let content: SourceSeriesModel.Content
    let refresh: () async -> Void
    @Query private var states: [SourceReadingState]
    @Environment(ServerStore.self) private var servers

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
            }
            Section {
                ForEach(content.chapters) { chapter in
                    SourceChapterRow(chapter: chapterRef(chapter), status: statuses[chapter.id]?.readingStatus ?? .new)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if content.chapters.isEmpty {
                ContentUnavailableView("No Chapters", systemImage: "books.vertical", description: Text("The source hasn't listed any chapters for this series."))
            }
        }
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
            chapterTitle: chapter.displayTitle
        )
    }

    /// The chapter you're partway through, or else the one after the last
    /// you finished, or the first. Sources list the newest chapter first,
    /// so reading order is the list reversed.
    private func nextToRead(statuses: [String: SourceReadingState]) -> ChekAPI.SourceChapter? {
        let inOrder = Array(content.chapters.reversed())
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
                    Text("^[\(count) chapter](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let summary = series.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
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
