import ChekReader
import Foundation

/// The shapes the Chek server sends, from its `openapi.yaml`.
///
/// The contract's own docs say clients generate their code from a tagged
/// release. There's no release yet, so these are written by hand and
/// cover only what the app reads; replace them with generated types once
/// one is tagged.
nonisolated enum ChekAPI {
    struct Session: Decodable, Sendable {
        var token: String
        var user: User
    }

    struct User: Decodable, Sendable {
        var id: Int64
        var name: String
        /// `admin` or `reader`.
        var role: String?

        var isAdmin: Bool { role == "admin" }
    }

    struct Library: Codable, Identifiable, Hashable, Sendable {
        var id: Int64
        var name: String
    }

    struct Series: Decodable, Identifiable, Hashable, Sendable {
        var id: Int64
        var libraryId: Int64
        var title: String
        var publicationCount: Int64
        var coverPublicationId: Int64?
    }

    struct PublicationSummary: Decodable, Identifiable, Hashable, Sendable {
        struct SeriesReference: Decodable, Hashable, Sendable {
            var id: Int64
            var title: String
        }

        var id: Int64
        var series: SeriesReference
        var title: String
        var numberLabel: String?
        var format: String
        var pageCount: Int?
        var available: Bool
        var hasCover: Bool

        var kind: PublicationKind {
            PublicationKind(serverFormat: format)
        }
    }

    struct Progress: Decodable, Sendable {
        var revision: Int64
        var locator: Locator?
        var device: String?
        var updatedAt: Date?
    }

    struct ContinueReadingItem: Decodable, Sendable {
        var publication: PublicationSummary
        var progress: Progress
    }

    struct PageInfo: Decodable, Sendable {
        var index: Int
        var mediaType: String
    }

    /// One page of a listing, with the cursor for the next one.
    struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
        var items: [Item]
        var nextCursor: String?
    }

    struct Items<Item: Decodable & Sendable>: Decodable, Sendable {
        var items: [Item]
    }

    struct ErrorBody: Decodable, Sendable {
        var code: String
        var message: String
    }

    struct ProgressConflict: Decodable, Sendable {
        var current: Progress
    }
}

/// What can go wrong talking to a Chek server, in terms the app acts on.
nonisolated enum ChekError: Error, Sendable {
    /// The session ended or was never valid; signing in again fixes it.
    case unauthorized
    case notFound
    /// Another device saved a position first.
    case progressConflict(ChekAPI.Progress)
    /// The server answered with an error the app doesn't handle specially.
    case server(status: Int, code: String?)
    /// The server couldn't be reached.
    case offline(URLError)
    /// The answer wasn't what the contract describes.
    case invalidResponse
}

extension ChekError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized: String(localized: "You're signed out.")
        case .notFound: String(localized: "This isn't available anymore.")
        case .progressConflict: String(localized: "Another device saved a different place.")
        case .server(_, "demo_account"): String(localized: "This is a demo, so nothing in it can be changed.")
        case .server(_, "source_failed"): String(localized: "This site isn't answering.")
        case .server(_, "source_unavailable"): String(localized: "This site isn't available right now.")
        case .server: String(localized: "Something went wrong.")
        case .offline: String(localized: "Couldn't connect.")
        case .invalidResponse: String(localized: "Something went wrong.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized: String(localized: "Sign in again to keep reading.")
        case .offline: String(localized: "Check that you're online and try again.")
        case .invalidResponse, .server(_, nil): String(localized: "Try again in a moment. If it keeps happening, let whoever shares this library know.")
        case .server(_, "source_failed"): String(localized: "It may be busy. Try again in a moment.")
        case .server(_, "source_unavailable"): String(localized: "It may have been removed. Check Sites to add it again.")
        default: nil
        }
    }
}
