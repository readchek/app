import Foundation

/// Something the reader can go on to from the publication it has open:
/// the next or previous chapter, volume or book in the same series.
enum ReadingTarget: Hashable {
    /// A chapter from the same source series.
    case chapter(SourceChapterRef)
    /// A publication in the same series on the same server.
    case publication(RemotePublication)
    /// A book in the same series in the on-device library.
    case book(UUID, title: String)

    var title: String {
        switch self {
        case .chapter(let chapter): chapter.chapterTitle
        case .publication(let publication): publication.displayTitle
        case .book(_, let title): title
        }
    }

    /// Whether it's a chapter rather than a volume or book, which is what
    /// the buttons that go to it call it.
    var isChapter: Bool {
        if case .chapter = self { true } else { false }
    }
}

/// What's known of one side of a publication in its series.
enum NeighborLookup: Equatable {
    /// Still being asked.
    case looking
    case found(ReadingTarget)
    /// Nothing further that way: the series' first or last.
    case end
    /// Nothing further yet: the latest chapter of a series that's still
    /// coming out.
    case caughtUp
    /// The server couldn't be reached and nothing kept on the device says.
    case unknown
    /// The publication isn't part of a series.
    case none

    var target: ReadingTarget? {
        if case .found(let target) = self { target } else { nil }
    }

    fileprivate init<Item: Equatable>(_ neighbor: ServerSync.Neighbor<Item>, as target: (Item) -> ReadingTarget) {
        switch neighbor {
        case .found(let item): self = .found(target(item))
        case .end: self = .end
        case .unknown: self = .unknown
        }
    }
}

/// Finds what's either side of a publication in its series, wherever it's
/// read from, and gets it ready to read.
@MainActor
struct NeighborFinder {
    let sync: ServerSync
    let library: LibraryStore
    let progress: ProgressStore

    func neighbors(of item: ReadingItem) async -> (previous: NeighborLookup, next: NeighborLookup) {
        if let chapter = item.sourceChapter {
            // The way on matters more, so it's asked for first.
            let next = await sync.chapter(after: chapter)
            let previous = await sync.chapter(before: chapter)
            var following = NeighborLookup(next, as: ReadingTarget.chapter)
            if following == .end, await isStillComingOut(chapter) {
                following = .caughtUp
            }
            return (NeighborLookup(previous, as: ReadingTarget.chapter), following)
        }
        if let publication = item.serverPublication {
            guard publication.seriesID != nil else { return (.none, .none) }
            let found = await sync.neighbors(of: publication)
            return (NeighborLookup(found.previous, as: ReadingTarget.publication), NeighborLookup(found.next, as: ReadingTarget.publication))
        }
        if case .local(let id) = item.ref, let book = library.book(id), book.seriesTitle?.isEmpty == false {
            let found = library.neighbors(of: book)
            return (
                found.previous.map { NeighborLookup.found(.book($0.id, title: $0.title)) } ?? NeighborLookup.end,
                found.next.map { NeighborLookup.found(.book($0.id, title: $0.title)) } ?? NeighborLookup.end
            )
        }
        return (.none, .none)
    }

    /// Whether the source's series may get more chapters. Sites mostly
    /// carry series still coming out, so one whose status isn't known is
    /// taken to be.
    private func isStillComingOut(_ chapter: SourceChapterRef) async -> Bool {
        let snapshot = await SeriesCache.read(server: chapter.server, source: chapter.source, series: chapter.seriesID)
        switch snapshot?.series.status {
        case "completed", "cancelled": return false
        default: return true
        }
    }

    /// What the reader needs to open `target`. One you've already read to
    /// the end starts from the beginning, since its last page is no place
    /// to pick it up again.
    func readingItem(for target: ReadingTarget) async throws(DisplayError) -> ReadingItem {
        var item: ReadingItem
        let isFinished: Bool
        switch target {
        case .chapter(let chapter):
            item = try await sync.readingItem(for: chapter)
            isFinished = progress.sourceState(chapter.ref)?.readingStatus == .finished
        case .publication(let publication):
            item = try await sync.readingItem(for: publication)
            isFinished = progress.readingState(publication.ref)?.readingStatus == .finished
        case .book(let id, _):
            guard let book = library.book(id) else {
                throw DisplayError(title: String(localized: "This Book Is No Longer in Your Library"))
            }
            item = ReadingItem(book)
            isFinished = book.readingStatus == .finished
        }
        if isFinished {
            item.startLocation = nil
        }
        return item
    }
}
