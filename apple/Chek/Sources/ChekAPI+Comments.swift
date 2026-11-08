import Foundation

/// The shapes of the server's comment routes, from its `openapi.yaml`.
///
/// Comments are read-only. They come from the site an extension reads,
/// only when the server's admin turned them on for a repository they
/// trust, and nothing here posts, votes or signs in.
nonisolated extension ChekAPI {
    /// The order a site lists comments in. `top` is the site's own ranking.
    enum CommentOrder: String, Codable, Hashable, Sendable {
        case top, newest, oldest
    }

    /// How many comments a chapter has, and where its thread is.
    struct CommentSummary: Decodable, Hashable, Sendable {
        var count: Int
        /// The thread on the site, always HTTPS.
        var url: String?
    }

    /// A stretch of a comment's text in one style. Styles that are off
    /// are left out.
    struct CommentRun: Decodable, Hashable, Sendable {
        var text: String
        var bold: Bool?
        var italic: Bool?
        var strike: Bool?
        var code: Bool?
        var spoiler: Bool?
        var quote: Bool?
        /// Always HTTPS.
        var link: String?
    }

    struct CommentAuthor: Decodable, Hashable, Sendable {
        var name: String
        var avatarUrl: String?
        /// A role the site shows beside the name, such as Uploader.
        var badge: String?
    }

    /// A comment as the site shows it, its text as styled runs rather
    /// than HTML.
    struct Comment: Decodable, Identifiable, Hashable, Sendable {
        var id: String
        var author: CommentAuthor
        var published: String?
        var edited: Bool
        var body: [CommentRun]
        /// Paths on the server for pictures attached to it.
        var images: [String]
        /// The whole comment is a spoiler.
        var spoiler: Bool
        var score: Int?
        /// For a reply to a reply, who it answers.
        var replyTo: String?
        var replyCount: Int
        /// The comment on the site, where it's reported. Always HTTPS.
        var url: String?

        var publishedDate: Date? {
            ChekAPI.date(published)
        }
    }

    struct CommentPage: Decodable, Sendable {
        var items: [Comment]
        /// The cursor for the next page, nil on the last.
        var next: String?
        var total: Int?
    }
}

extension ChekAPI.InstalledExtension {
    /// The orders its comments come in, the site's default first, when it
    /// gives comments. Orders this app doesn't know yet are left out.
    var commentOrders: [ChekAPI.CommentOrder]? {
        comments.map { $0.compactMap(ChekAPI.CommentOrder.init(rawValue:)) }
    }
}
