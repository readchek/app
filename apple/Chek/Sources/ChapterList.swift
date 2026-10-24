import Foundation
import Observation

/// A series' chapters a page at a time, oldest or newest first, so a long
/// manga shows its first chapters at once and loads the rest as you scroll
/// or jump, rather than every chapter before any shows. The pages loaded
/// are one run without gaps, in the order shown, and each page seen is
/// kept on the device for reading offline.
@MainActor
@Observable
final class ChapterList {
    typealias Order = ChekClient.ChapterOrder
    typealias Entry = SeriesCache.KnownChapter

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// Reading a page before or after the ones shown.
        case loadingMore
        case failed(DisplayError)
    }

    /// Chapters asked for at once: a screenful many times over, small
    /// enough to arrive quickly.
    static let pageSize = 100

    private(set) var order: Order
    private(set) var phase = Phase.idle
    /// The loaded chapters, in the order shown.
    private(set) var entries: [Entry] = []
    /// How many releases the series has, once a page has said. Sites
    /// often list a chapter once per group that released it, so this can
    /// be far more than its chapters.
    private(set) var total: Int?
    /// How many chapters, when the server has read the whole list.
    private(set) var chapterCount: Int?
    /// The release group you prefer for this series, whose release of each
    /// chapter is the one shown.
    private(set) var preferredGroup: String?
    /// Where `entries` starts, counted in releases from the end `order`
    /// names.
    private(set) var start = 0
    /// Where the page after the loaded ones starts, or nil at the end.
    private(set) var nextOffset: Int?
    /// Why the last page before or after couldn't be read, while the
    /// others still show.
    private(set) var moreFailure: DisplayError?
    /// The series' first chapter, once asked for, for starting it from a
    /// list that opens newest first.
    private(set) var first: ChekAPI.SourceChapter?
    /// Whether these came from the device because the server couldn't be
    /// reached, in which case there's nothing more to page through.
    private(set) var isOffline = false

    private let server: UUID
    private let source: String
    private let seriesID: String
    private let servers: ServerStore
    /// Told about each page read, so it can be kept with the series.
    @ObservationIgnored var onPage: (([Entry], Int) -> Void)?
    /// Drops pages answered after the list was started over.
    @ObservationIgnored private var generation = 0

    init(server: UUID, source: String, seriesID: String, order: Order, servers: ServerStore) {
        self.server = server
        self.source = source
        self.seriesID = seriesID
        self.order = order
        self.servers = servers
    }

    var hasMoreAfter: Bool {
        !isOffline && nextOffset != nil
    }

    var hasMoreBefore: Bool {
        !isOffline && start > 0
    }

    /// The series in runs of a page, by position in reading order, for
    /// jumping straight to one: 1–100, 101–200 and so on. Only when each
    /// chapter has one release, since positions count releases and the
    /// runs would otherwise be labelled with numbers no chapter has.
    var ranges: [ClosedRange<Int>] {
        guard let total, total > Self.pageSize, chapterCount == total else { return [] }
        return stride(from: 1, through: total, by: Self.pageSize).map { $0...min($0 + Self.pageSize - 1, total) }
    }

    /// Reads the first page, or the page the list is at, again.
    func load(refresh: Bool = false) async {
        await reload(at: start, refresh: refresh)
    }

    /// Shows a page that has `chapterID` a little way down, so the chapter
    /// you're reading opens with a few before it, oldest first.
    func load(around chapterID: String) async {
        order = .oldestFirst
        guard let page = try? await fetch(after: chapterID, limit: 1) else {
            await reload(at: 0, refresh: false)
            return
        }
        // Just past the chapter is where it stands, counted from 1.
        await reload(at: max(0, page.offset - 1 - 20), refresh: false)
    }

    /// Shows the chapters from the other end.
    func setOrder(_ order: Order) async {
        guard order != self.order else { return }
        self.order = order
        await reload(at: 0, refresh: false)
    }

    /// Shows the run of chapters starting at `position` in reading order,
    /// in the current order.
    func jump(to range: ClosedRange<Int>) async {
        guard let total else { return }
        let offset = order == .oldestFirst ? range.lowerBound - 1 : total - range.upperBound
        await reload(at: max(0, offset), refresh: false)
    }

    /// Adds the page after the loaded ones, as the last row comes into view.
    func loadMore() async {
        guard hasMoreAfter, phase == .loaded else { return }
        let generation = generation
        phase = .loadingMore
        do {
            let page = try await fetch(offset: nextOffset ?? 0, limit: Self.pageSize)
            guard generation == self.generation else { return }
            let seen = Set(entries.map(\.id))
            entries += page.known(order).filter { !seen.contains($0.id) }
            take(page)
            moreFailure = nil
            onPage?(page.known(order), page.total)
        } catch {
            guard generation == self.generation else { return }
            moreFailure = DisplayError(error)
        }
        phase = .loaded
    }

    /// Adds the page before the loaded ones, after a jump into the middle.
    func loadEarlier() async {
        guard hasMoreBefore, phase == .loaded else { return }
        let generation = generation
        let offset = max(0, start - Self.pageSize)
        phase = .loadingMore
        do {
            let page = try await fetch(offset: offset, limit: start - offset)
            guard generation == self.generation else { return }
            // A page from an earlier offset can run into the loaded ones,
            // since it counts chapters and offsets count releases.
            let seen = Set(entries.map(\.id))
            let next = nextOffset
            entries = page.known(order).filter { !seen.contains($0.id) } + entries
            start = offset
            take(page)
            nextOffset = next
            moreFailure = nil
            onPage?(page.known(order), page.total)
        } catch {
            guard generation == self.generation else { return }
            moreFailure = DisplayError(error)
        }
        phase = .loaded
    }

    /// The first chapter in reading order, from what's loaded when it's
    /// there, else from the server.
    func firstChapter() async -> ChekAPI.SourceChapter? {
        if let first = entries.first(where: { $0.position == 1 }) {
            return first.chapter
        }
        if let first {
            return first
        }
        first = try? await fetch(offset: 0, limit: 1, order: .oldestFirst).items.first
        return first
    }

    private func reload(at offset: Int, refresh: Bool) async {
        generation += 1
        let generation = generation
        if entries.isEmpty {
            phase = .loading
        }
        do {
            let page = try await fetch(offset: offset, limit: Self.pageSize, refresh: refresh)
            guard generation == self.generation else { return }
            entries = page.known(order)
            start = page.offset
            take(page)
            isOffline = false
            moreFailure = nil
            phase = .loaded
            onPage?(entries, page.total)
        } catch {
            guard generation == self.generation else { return }
            // What was seen before stands in, so downloaded chapters can
            // be read offline; a list already showing just stays.
            if !entries.isEmpty {
                moreFailure = DisplayError(error)
                phase = .loaded
            } else if let snapshot = await SeriesCache.read(server: server, source: source, series: seriesID), !snapshot.chapters.isEmpty {
                entries = order == .oldestFirst ? snapshot.chapters : snapshot.chapters.reversed()
                total = snapshot.total
                start = 0
                isOffline = true
                phase = .loaded
            } else {
                phase = .failed(DisplayError(error))
            }
        }
    }

    /// Chooses whose release of each chapter is shown for this series, on
    /// every device, or goes back to the default pick for nil. Pages loaded
    /// already are reordered here, since cached ones keep the old pick.
    func prefer(group: String?) async {
        preferredGroup = group
        entries = entries.map { Entry(position: $0.position, chapter: $0.chapter.preferring(group: group)) }
        let seriesID = seriesID
        let source = source
        try? await servers.request(server) { client throws(ChekError) in
            try await client.setReleaseGroup(group, forSeries: seriesID, inSource: source)
        }
    }

    /// What a page says about the whole series, and where the next starts.
    private func take(_ page: ChekAPI.SourceChapterPage) {
        total = page.total
        nextOffset = page.nextOffset
        if let count = page.chapterCount {
            chapterCount = count
        }
        preferredGroup = page.preferredGroup
    }

    private func fetch(offset: Int = 0, after: String? = nil, limit: Int, order: Order? = nil, refresh: Bool = false) async throws(ChekError) -> ChekAPI.SourceChapterPage {
        let seriesID = seriesID
        let source = source
        let order = order ?? self.order
        return try await servers.request(server) { client throws(ChekError) in
            try await client.chapterPage(ofSeries: seriesID, inSource: source, order: order, offset: offset, after: after, limit: limit, refresh: refresh)
        }
    }
}
