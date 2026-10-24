import Foundation

/// The shapes of the server's extension routes, from its `openapi.yaml`.
///
/// Extensions run on the server, sandboxed; the app only lists them and
/// reads what they find, through the server.
nonisolated extension ChekAPI {
    /// An extension you've installed, which is a source you can browse.
    struct InstalledExtension: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var version: String
        var repositoryId: Int64
        var sites: [String]
        var languages: [String]
        /// False while it came from your own repository and the admin
        /// allows only the allow list.
        var usable: Bool
        /// The version the repository lists, when it's newer.
        var update: String?
    }

    /// An extension a repository offers.
    struct AvailableExtension: Decodable, Identifiable, Hashable, Sendable {
        var repositoryId: Int64
        var id: String
        var name: String
        var version: String
        var sites: [String]
        var languages: [String]
        var capabilities: [String]
        /// The version installed from this repository, if any.
        var installedVersion: String?

        /// Unique across repositories, which can each offer the same id.
        var listingID: String { "\(repositoryId)/\(id)" }
    }

    struct ExtensionRepository: Decodable, Identifiable, Hashable, Sendable {
        var id: Int64
        var url: String
        var name: String?
        var allowListed: Bool
        var usable: Bool
        var extensionCount: Int
        /// When the index was last read, nil until it has been.
        var fetchedAt: Date?
        var fetchError: String?
        /// Whether the server keeps credentials for it, which it never
        /// sends back. Absent from servers before private repositories.
        var hasCredentials: Bool?
    }

    /// How the server signs in to a private repository. It sends them only
    /// to the repository's own site.
    enum RepositoryCredentials: Encodable, Hashable, Sendable {
        /// `Authorization: Bearer`, such as a GitHub access token.
        case bearer(token: String)
        case basic(username: String, password: String)
        /// Any other header, such as an API key.
        case header(name: String, value: String)
        /// Several headers, such as a Cloudflare Access service token's ID
        /// and secret. Servers before Chek's repository format 1 don't take it.
        case headers([NamedHeader])

        struct NamedHeader: Encodable, Hashable, Sendable {
            var name: String
            var value: String
        }

        private enum CodingKeys: String, CodingKey {
            case type, token, username, password, name, value, headers
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .bearer(let token):
                try container.encode("bearer", forKey: .type)
                try container.encode(token, forKey: .token)
            case .basic(let username, let password):
                try container.encode("basic", forKey: .type)
                try container.encode(username, forKey: .username)
                try container.encode(password, forKey: .password)
            case .header(let name, let value):
                try container.encode("header", forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encode(value, forKey: .value)
            case .headers(let headers):
                try container.encode("headers", forKey: .type)
                try container.encode(headers, forKey: .headers)
            }
        }
    }

    /// Server-wide settings everyone can read and only an admin changes.
    struct ServerSettings: Codable, Hashable, Sendable {
        /// Whether people other than the admin may add repositories, which
        /// only they see.
        var allowAnyRepository: Bool
    }

    /// A series as a source lists it.
    struct SourceSeriesItem: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var title: String
        /// A path on the server that serves the image.
        var coverUrl: String?
    }

    struct SourceSearchPage: Decodable, Sendable {
        var items: [SourceSeriesItem]
        var hasMore: Bool
    }

    struct SourceSeries: Codable, Hashable, Sendable {
        struct Contributor: Codable, Hashable, Sendable {
            var name: String
            var role: String
        }

        var id: String
        var title: String
        var summary: String?
        var coverUrl: String?
        var contributors: [Contributor]
        /// `ltr`, `rtl` or `ttb`, when the source knows.
        var readingDirection: String?
        /// `ongoing`, `completed`, `hiatus` or `cancelled`, when the source
        /// knows. Absent from servers older than the 0.3.0 source contract.
        var status: String?
        /// The year the series started, when the source knows.
        var year: Int?
        /// Genres and themes as the source names them, most important first.
        var tags: [String]?

        init(id: String, title: String, summary: String?, coverUrl: String?, contributors: [Contributor], readingDirection: String?, status: String? = nil, year: Int? = nil, tags: [String]? = nil) {
            self.id = id
            self.title = title
            self.summary = summary
            self.coverUrl = coverUrl
            self.contributors = contributors
            self.readingDirection = readingDirection
            self.status = status
            self.year = year
            self.tags = tags
        }
    }

    struct SourceChapter: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var title: String
        /// As the source writes it, such as "12" or "Vol. 2".
        var number: String?
        var published: String?

        /// `published` as a date, however the source wrote it: with
        /// fractions of a second, without, or as a bare day.
        var publishedDate: Date? {
            guard let published else { return nil }
            return ISO8601DateFormatter.withFractionalSeconds.date(from: published)
                ?? ISO8601DateFormatter.plain.date(from: published)
                ?? ISO8601DateFormatter.dateOnly.date(from: published)
        }
    }

    struct SourcePage: Decodable, Sendable {
        var index: Int
        /// A path on the server that serves the image.
        var url: String
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
