import SwiftData
import SwiftUI

/// What you read most recently and haven't finished, from the device or a
/// server, so it can be resumed from anywhere in the app.
struct NowReading {
    enum Source {
        case local(Book)
        case remote(RemotePublication)
        case chapter(SourceChapterRef)
    }

    let source: Source
    let title: String
    let progress: Double?
    let cover: CoverSource

    var ref: PublicationRef {
        switch source {
        case .local(let book): book.ref
        case .remote(let publication): publication.ref
        case .chapter(let chapter): chapter.ref
        }
    }

    /// The newest of the latest book, server publication and source chapter.
    static func latest(book: Book?, remote: RemoteReadingState?, chapter: SourceReadingState?, servers: ServerStore, downloads: Downloads) -> NowReading? {
        // Server content you're signed out of would open to an alert, so
        // the bar falls back to what can open: a download opens anyway.
        let remote = remote.flatMap { servers.state(of: $0.serverID) == .signedIn || downloads.isDownloaded($0.ref) ? $0 : nil }
        let chapter = chapter.flatMap { servers.state(of: $0.serverID) == .signedIn || downloads.isDownloaded($0.ref) ? $0 : nil }
        let bookDate = book?.lastOpenedAt ?? .distantPast
        let remoteDate = remote?.lastOpenedAt ?? .distantPast
        let chapterDate = chapter?.lastOpenedAt ?? .distantPast
        if let chapter, chapterDate > bookDate, chapterDate > remoteDate {
            return NowReading(
                source: .chapter(SourceChapterRef(chapter)),
                title: chapter.seriesTitle,
                progress: chapter.progress,
                cover: servers.sourceImage(chapter.seriesCoverPath, on: chapter.serverID)
            )
        }
        if let book, bookDate >= remoteDate {
            return NowReading(source: .local(book), title: book.title, progress: book.progress, cover: book.coverURL.map(CoverSource.file) ?? .none)
        }
        if let remote {
            let publication = RemotePublication(remote)
            return NowReading(
                source: .remote(publication),
                title: publication.displayTitle,
                progress: remote.progress,
                cover: servers.cover(of: publication.id, on: publication.server)
            )
        }
        return nil
    }
}

extension View {
    /// Shows what you're reading in a glass bar above the tab bar, as Music
    /// shows what's playing.
    func nowReadingAccessory() -> some View {
        modifier(NowReadingAccessoryModifier())
    }
}

private struct NowReadingAccessoryModifier: ViewModifier {
    @Query(filter: #Predicate<Book> { $0.lastOpenedAt != nil && $0.finishedAt == nil }, sort: \Book.lastOpenedAt, order: .reverse)
    private var books: [Book]
    @Query(filter: #Predicate<RemoteReadingState> { $0.lastOpenedAt != nil }, sort: \RemoteReadingState.lastOpenedAt, order: .reverse)
    private var remote: [RemoteReadingState]
    @Query(filter: #Predicate<SourceReadingState> { $0.lastOpenedAt != nil }, sort: \SourceReadingState.lastOpenedAt, order: .reverse)
    private var chapters: [SourceReadingState]
    @Environment(ServerStore.self) private var servers
    @Environment(Downloads.self) private var downloads

    func body(content: Content) -> some View {
        let current = NowReading.latest(
            book: books.first,
            remote: remote.first { $0.readingStatus != .finished },
            chapter: chapters.first { $0.readingStatus != .finished },
            servers: servers,
            downloads: downloads
        )
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: current != nil) {
                if let current {
                    NowReadingBar(current: current)
                }
            }
        } else if let current {
            content.tabViewBottomAccessory {
                NowReadingBar(current: current)
            }
        } else {
            content
        }
    }
}

private struct NowReadingBar: View {
    let current: NowReading
    @Environment(AppRouter.self) private var router
    @Environment(ServerSync.self) private var sync
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: resume) {
            HStack(spacing: 12) {
                CoverView(source: current.cover, title: current.title, cornerRadius: 3)
                    .frame(width: 24)
                    .readerTransitionSource(current.ref)
                VStack(alignment: .leading, spacing: 0) {
                    Text(current.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if placement != .inline, let progress = current.progress, progress >= 0.01 {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .font(.body)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Continue \(current.title)"))
    }

    private func resume() {
        switch current.source {
        case .local(let book): router.open(ReadingItem(book))
        case .remote(let publication): router.open(publication, using: sync)
        case .chapter(let chapter): router.open(chapter, using: sync)
        }
    }
}
