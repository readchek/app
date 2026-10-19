import Foundation
import SwiftData

extension ChekSchemaV1 {
    /// A server you've signed in to. Its session token is kept in the
    /// Keychain under ``id``, never here.
    ///
    /// Only ``ServerStore`` changes accounts.
    @Model
    final class ServerAccount {
        @Attribute(.unique) var id: UUID
        /// ``ServerKind`` as stored.
        var kindRawValue: String
        /// What the account is called in Chek, which starts as the server's
        /// host name.
        var name: String
        var baseURL: URL
        var userName: String
        var userID: Int64?
        var addedAt: Date
        /// The account's place in lists, lowest first.
        var sortIndex: Int

        init(id: UUID = UUID(), kind: ServerKind, name: String, baseURL: URL, userName: String, userID: Int64?, sortIndex: Int, at date: Date = .now) {
            self.id = id
            kindRawValue = kind.rawValue
            self.name = name
            self.baseURL = baseURL
            self.userName = userName
            self.userID = userID
            addedAt = date
            self.sortIndex = sortIndex
        }

        var kind: ServerKind {
            ServerKind(rawValue: kindRawValue) ?? .chek
        }
    }
}

/// The kinds of server Chek reads from.
nonisolated enum ServerKind: String, Codable, Sendable, CaseIterable {
    case chek
}
