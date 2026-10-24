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
    @State private var chapters: ChapterList?

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
                switch chapters?.phase ?? .idle {
                case .idle, .loading:
                    ProgressView()
                case .failed(let error):
                    FailureState(error: error) {
                        await chapters?.load(around: chapter.chapterID)
                    }
                case .loaded, .loadingMore:
                    if let chapters {
                        list(chapters)
                    }
                }
            }
            .navigationTitle(chapter.seriesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard chapters == nil else { return }
            let list = ChapterList(server: chapter.server, source: chapter.source, seriesID: chapter.seriesID, order: .oldestFirst, servers: servers)
            chapters = list
            await list.load(around: chapter.chapterID)
        }
    }

    /// The loaded run of chapters, scrolled to the one you're in, growing
    /// a page at a time at either end.
    private func list(_ chapters: ChapterList) -> some View {
        ScrollViewReader { proxy in
            List {
                if chapters.hasMoreBefore {
                    Button("Show Earlier Chapters", systemImage: "arrow.up") {
                        Task { await chapters.loadEarlier() }
                    }
                }
                ForEach(chapters.entries) { entry in
                    row(entry.chapter)
                        .id(entry.chapter.id)
                        .onAppear {
                            if entry.id == chapters.entries.last?.id {
                                Task { await chapters.loadMore() }
                            }
                        }
                }
                if chapters.phase == .loadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .onAppear {
                proxy.scrollTo(chapter.chapterID, anchor: .center)
            }
        }
    }

    private func row(_ item: ChekAPI.SourceChapter) -> some View {
        let isCurrent = item.id == chapter.chapterID
        return Button {
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
                    StatusText(status: status)
                }
            }
            .contentShape(.rect)
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
