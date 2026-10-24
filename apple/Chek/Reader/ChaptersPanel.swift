import SwiftData
import SwiftUI

/// For a chapter read from a source, the series' other chapters, with the
/// one you're in marked and how far you are in each, so you can move
/// between chapters without leaving the reader.
struct ChaptersPanel: View {
    let session: ReaderSession
    let chapter: SourceChapterRef
    let open: (ReadingItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Query private var states: [SourceReadingState]
    @State private var chapters: LoadState<[ChekAPI.SourceChapter]> = .idle

    init(session: ReaderSession, chapter: SourceChapterRef, open: @escaping (ReadingItem) -> Void) {
        self.session = session
        self.chapter = chapter
        self.open = open
        let server = chapter.server
        let source = chapter.source
        let series = chapter.seriesID
        _states = Query(filter: #Predicate<SourceReadingState> {
            $0.serverID == server && $0.sourceID == source && $0.seriesID == series
        })
    }

    var body: some View {
        NavigationStack {
            Group {
                switch chapters {
                case .idle, .loading:
                    ProgressView()
                case .failed(let error):
                    FailureState(error: error)
                case .loaded(let chapters):
                    ScrollViewReader { proxy in
                        List(chapters) { item in
                            let isCurrent = item.id == chapter.chapterID
                            Button {
                                guard !isCurrent, let next = try? sync.readingItem(for: ref(item)) else {
                                    dismiss()
                                    return
                                }
                                dismiss()
                                open(next)
                            } label: {
                                HStack {
                                    Text(item.displayTitle)
                                        .fontWeight(isCurrent ? .semibold : .regular)
                                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                    Spacer()
                                    if isCurrent {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.tint)
                                            .accessibilityLabel(Text("Current chapter"))
                                    } else if let status = statuses[item.id], status != .new {
                                        StatusText(status: status, fallback: nil)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .id(item.id)
                        }
                        .listStyle(.plain)
                        .onAppear {
                            proxy.scrollTo(chapter.chapterID, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(chapter.seriesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard case .idle = chapters else { return }
            chapters = .loading
            do {
                let listed = try await servers.request(chapter.server) { client throws(ChekError) in
                    try await client.chapters(ofSeries: chapter.seriesID, inSource: chapter.source)
                }
                chapters = .loaded(listed)
            } catch {
                // What the source said last time, when it can't be reached.
                if let cached = await SeriesCache.read(server: chapter.server, source: chapter.source, series: chapter.seriesID) {
                    chapters = .loaded(cached.chapters)
                } else {
                    chapters = .failed(DisplayError(error))
                }
            }
        }
    }

    private var statuses: [String: ReadingStatus] {
        Dictionary(states.map { ($0.chapterID, $0.readingStatus) }, uniquingKeysWith: { first, _ in first })
    }

    private func ref(_ item: ChekAPI.SourceChapter) -> SourceChapterRef {
        SourceChapterRef(
            server: chapter.server,
            source: chapter.source,
            seriesID: chapter.seriesID,
            seriesTitle: chapter.seriesTitle,
            chapterID: item.id,
            chapterTitle: item.displayTitle,
            isRightToLeft: chapter.isRightToLeft,
            seriesCoverPath: chapter.seriesCoverPath
        )
    }
}
