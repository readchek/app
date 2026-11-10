import Foundation
import Observation

/// Readers' comments on a chapter read from a source, as its site shows
/// them: whether there are any, then a page at a time in the order chosen,
/// with each comment's replies loaded when asked for.
///
/// Comments come only through extensions the server's admin trusts with
/// them, and only for reading. Nothing here posts or votes.
@MainActor
@Observable
final class ChapterComments {
    /// Whether the chapter has comments to show.
    enum Availability: Equatable {
        case looking
        /// The site gives none here, or the chapter has none.
        case none
        /// `count` comments, with the thread on the site when it's known.
        case available(count: Int, thread: URL?)
    }

    /// The comments, a page at a time. One phase, so loading, failing and
    /// what's shown never disagree.
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case loadingMore
        case failed(DisplayError)
    }

    /// A comment's replies, once asked for.
    enum Replies: Equatable {
        case loading
        case loaded([ChekAPI.Comment], next: String?)
        case failed
    }

    let chapter: SourceChapterRef
    private(set) var availability = Availability.looking
    /// The site's name, as its extension is called.
    private(set) var site = ""
    /// The orders the site offers, its default first. Empty when it gives
    /// only a count, which leaves the thread on the site.
    private(set) var orders: [ChekAPI.CommentOrder] = []
    private(set) var order: ChekAPI.CommentOrder?
    private(set) var phase = Phase.idle
    private(set) var items: [ChekAPI.Comment] = []
    /// The cursor for the page after the loaded ones, nil at the end.
    private(set) var next: String?
    /// Why the page after the loaded ones couldn't be read.
    private(set) var moreFailed = false
    private(set) var replies: [String: Replies] = [:]

    /// Whether the chapter's site shows comments at all, whatever this
    /// chapter has. The reader keeps a place for comments on every chapter
    /// of such a site, so the button never comes and goes between chapters.
    private(set) var isSupported: Bool
    /// The sites found to show comments, by server and source, so the next
    /// chapter of one knows before it has asked.
    private static var supporting: Set<String> = []

    private var siteKey: String { "\(chapter.server.uuidString)/\(chapter.source)" }

    private let servers: ServerStore
    /// Counts loads, so an answer for an order no longer chosen is dropped.
    private var generation = 0

    init(chapter: SourceChapterRef, servers: ServerStore) {
        self.chapter = chapter
        self.servers = servers
        isSupported = Self.supporting.contains("\(chapter.server.uuidString)/\(chapter.source)")
    }

    /// Whether there's a list to open here, rather than only a link to
    /// the thread on the site.
    var hasList: Bool { !orders.isEmpty }

    var count: Int? {
        if case .available(let count, _) = availability { count } else { nil }
    }

    var thread: URL? {
        if case .available(_, let thread) = availability { thread } else { nil }
    }

    /// Finds out whether the chapter has comments. Any failure reads as
    /// none: comments are extra, and never stand in the way of reading.
    func look() async {
        availability = .looking
        let chapter = chapter
        do {
            let extensions = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.installedExtensions()
            }
            guard let source = extensions.first(where: { $0.id == chapter.source }), let orders = source.commentOrders else {
                availability = .none
                isSupported = false
                Self.supporting.remove(siteKey)
                return
            }
            isSupported = true
            Self.supporting.insert(siteKey)
            site = source.name
            self.orders = orders
            order = orders.first
            let summary = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.commentSummary(ofChapter: chapter.chapterID, inSource: chapter.source)
            }
            guard let summary, summary.count > 0 else {
                availability = .none
                return
            }
            availability = .available(count: summary.count, thread: summary.url.flatMap(Self.safeLink))
        } catch {
            availability = .none
        }
    }

    /// Loads the first page, unless it's loaded or loading.
    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    /// Loads the first page again, in the order chosen.
    func load() async {
        generation += 1
        let generation = generation
        phase = .loading
        moreFailed = false
        do {
            let page = try await fetchPage(cursor: nil)
            guard generation == self.generation else { return }
            items = page.items
            next = page.next
            phase = .loaded
        } catch {
            guard generation == self.generation else { return }
            phase = .failed(DisplayError(error))
        }
    }

    /// Lists the comments in another order, from the top.
    func choose(_ order: ChekAPI.CommentOrder) async {
        guard order != self.order else { return }
        self.order = order
        items = []
        replies = [:]
        await load()
    }

    /// Loads the page after the loaded ones. One at a time.
    func loadMore() async {
        guard phase == .loaded, let cursor = next else { return }
        let generation = generation
        phase = .loadingMore
        moreFailed = false
        do {
            let page = try await fetchPage(cursor: cursor)
            guard generation == self.generation else { return }
            // A site that shifts as people post can repeat a comment.
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            next = page.next
        } catch {
            guard generation == self.generation else { return }
            moreFailed = true
        }
        phase = .loaded
    }

    /// Loads a comment's replies, or more of them.
    func loadReplies(of comment: ChekAPI.Comment) async {
        let cursor: String?
        var earlier: [ChekAPI.Comment] = []
        switch replies[comment.id] {
        case .loading: return
        case .loaded(let loaded, let next):
            guard let next else { return }
            earlier = loaded
            cursor = next
        case .failed, nil:
            cursor = nil
        }
        if earlier.isEmpty {
            replies[comment.id] = .loading
        }
        let chapter = chapter
        do {
            let page = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.replies(to: comment.id, ofChapter: chapter.chapterID, inSource: chapter.source, cursor: cursor)
            }
            replies[comment.id] = .loaded(earlier + page.items, next: page.next)
        } catch {
            replies[comment.id] = earlier.isEmpty ? .failed : .loaded(earlier, next: cursor)
        }
    }

    /// Hides a comment's replies again.
    func closeReplies(of comment: ChekAPI.Comment) {
        replies[comment.id] = nil
    }

    private func fetchPage(cursor: String?) async throws(ChekError) -> ChekAPI.CommentPage {
        let chapter = chapter
        let order = order
        return try await servers.request(chapter.server) { client throws(ChekError) in
            try await client.comments(ofChapter: chapter.chapterID, inSource: chapter.source, order: order, cursor: cursor)
        }
    }

    /// A link from a site, followed only when it's HTTPS, as the server
    /// promises; anything else is dropped rather than opened.
    nonisolated static func safeLink(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        return url
    }
}
