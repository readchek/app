import Foundation
import Observation
import SwiftData
import UserNotifications

/// Owns the series you follow from sources: following, unfollowing and
/// checking them for new chapters. Views read follows with `@Query`.
@MainActor
@Observable
final class FollowStore {
    /// New chapters one check found in a series.
    struct NewChapters: Sendable {
        let key: String
        let server: UUID
        let source: String
        let seriesID: String
        let title: String
        let count: Int
    }

    /// Whether a check for new chapters is running.
    private(set) var isChecking = false

    private let context: ModelContext
    private let servers: ServerStore
    @ObservationIgnored private var lastCheck: Date?

    init(context: ModelContext, servers: ServerStore) {
        self.context = context
        self.servers = servers
    }

    /// Follows a series that lists `count` chapters now, so only chapters
    /// after those count as new.
    func follow(_ series: ChekAPI.SourceSeries, count: Int, server: UUID, source: String) {
        guard followed(server: server, source: source, series: series.id) == nil else { return }
        let follow = FollowedSeries(
            serverID: server,
            sourceID: source,
            seriesID: series.id,
            title: series.title,
            coverPath: series.coverUrl,
            isRightToLeft: series.readingDirection == "rtl",
            chapterCount: count
        )
        follow.lastCheckedAt = .now
        let isFirst = ((try? context.fetchCount(FetchDescriptor<FollowedSeries>())) ?? 0) == 0
        context.insert(follow)
        save()
        if isFirst {
            Task { await FollowNotifications.askIfNeeded() }
        }
    }

    func unfollow(_ follow: FollowedSeries) {
        context.delete(follow)
        save()
    }

    func followed(server: UUID, source: String, series: String) -> FollowedSeries? {
        let key = FollowedSeries.key(server: server, source: source, series: series)
        var descriptor = FetchDescriptor<FollowedSeries>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Notes that you've seen the series' chapters, so none count as new.
    func didOpen(server: UUID, source: String, series: ChekAPI.SourceSeries, count: Int) {
        guard let follow = followed(server: server, source: source, series: series.id) else { return }
        follow.unseenChapterIDs = []
        follow.chapterCount = count
        follow.title = series.title
        follow.coverPath = series.coverUrl
        follow.lastCheckedAt = .now
        save()
        updateBadge()
    }

    /// Asks each followed series' source for its chapters and notes the
    /// ones you haven't seen, giving back what this check turned up.
    /// Skipped when checked recently, since every check is a request to
    /// the source's site per series.
    @discardableResult
    func checkForNewChapters(force: Bool = false) async -> [NewChapters] {
        if !force, let lastCheck, Date.now.timeIntervalSince(lastCheck) < 15 * 60 { return [] }
        guard !isChecking else { return [] }
        isChecking = true
        defer { isChecking = false }
        lastCheck = .now
        var found: [NewChapters] = []
        let follows = (try? context.fetch(FetchDescriptor<FollowedSeries>())) ?? []
        for follow in follows where servers.state(of: follow.serverID) == .signedIn {
            if Task.isCancelled { break }
            let server = follow.serverID
            let source = follow.sourceID
            let seriesID = follow.seriesID
            // New chapters are the newest ones, so the first page newest
            // first holds them, with the count to tell how many; a series
            // with more new than a page asks for that many.
            let known = follow.chapterCount
            func newest(_ limit: Int) async -> ChekAPI.SourceChapterPage? {
                try? await servers.request(server) { client throws(ChekError) in
                    try await client.chapterPage(ofSeries: seriesID, inSource: source, order: .newestFirst, limit: limit)
                }
            }
            guard var page = await newest(50) else { continue }
            if page.total - known > page.items.count, page.items.count == 50 {
                page = await newest(min(page.total - known, 500)) ?? page
            }
            // The page is kept, so the Updates list can name the new
            // chapters without asking again.
            await SeriesCache.mergeChapters(page.known(.newestFirst), total: page.total, server: server, source: source, series: ChekAPI.SourceSeries(
                id: seriesID,
                title: follow.title,
                summary: nil,
                coverUrl: follow.coverPath,
                contributors: [],
                readingDirection: follow.isRightToLeft ? "rtl" : nil
            ))
            // A first check after following knows the chapters you saw;
            // anything beyond that count and not read is new.
            let read = Set(readChapterIDs(follow))
            if page.total > known {
                let unseen = Set(follow.unseenChapterIDs)
                let fresh = page.items.prefix(page.total - known).map(\.id).filter { !unseen.contains($0) && !read.contains($0) }
                follow.unseenChapterIDs.append(contentsOf: fresh)
                follow.chapterCount = page.total
                if !fresh.isEmpty {
                    found.append(NewChapters(key: follow.key, server: server, source: source, seriesID: seriesID, title: follow.title, count: fresh.count))
                }
            }
            follow.lastCheckedAt = .now
        }
        save()
        if !found.isEmpty {
            updateBadge()
        }
        return found
    }

    /// Notes that you've seen one new chapter, as when opening it from
    /// the Updates list.
    func markSeen(chapterID: String, in follow: FollowedSeries) {
        guard follow.unseenChapterIDs.contains(chapterID) else { return }
        follow.unseenChapterIDs.removeAll { $0 == chapterID }
        save()
        updateBadge()
    }

    /// Clears what's new in every followed series.
    func markAllSeen() {
        for follow in (try? context.fetch(FetchDescriptor<FollowedSeries>())) ?? [] where !follow.unseenChapterIDs.isEmpty {
            follow.unseenChapterIDs = []
        }
        save()
        updateBadge()
    }

    /// How many chapters are new across every followed series.
    var unseenCount: Int {
        ((try? context.fetch(FetchDescriptor<FollowedSeries>())) ?? []).reduce(0) { $0 + $1.unseenChapterIDs.count }
    }

    /// Puts the count of new chapters on the app's icon, as the Reading
    /// Now tab shows it, and takes it off once they're seen.
    func updateBadge() {
        let count = unseenCount
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    private func readChapterIDs(_ follow: FollowedSeries) -> [String] {
        let server = follow.serverID
        let source = follow.sourceID
        let series = follow.seriesID
        let states = (try? context.fetch(FetchDescriptor<SourceReadingState>(predicate: #Predicate {
            $0.serverID == server && $0.sourceID == source && $0.seriesID == series
        }))) ?? []
        return states.filter { $0.lastOpenedAt != nil }.map(\.chapterID)
    }

    private func save() {
        try? context.save()
    }
}
