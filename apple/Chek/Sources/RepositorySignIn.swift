import Foundation

/// What the sign-in form for a private repository holds, before it's sent
/// as ``ChekAPI/RepositoryCredentials``.
///
/// Every kind keeps its own fields, so switching kinds and back doesn't
/// lose what was typed.
nonisolated struct RepositorySignIn: Equatable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        /// A public repository.
        case none
        case token
        case password
        case header

        var id: Self { self }
    }

    var kind = Kind.none
    var token = ""
    var username = ""
    var password = ""
    var headerName = ""
    var headerValue = ""

    /// Whether every field the kind needs is filled in.
    var isComplete: Bool {
        switch kind {
        case .none: true
        case .token: !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .password: !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .header: !headerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !headerValue.isEmpty
        }
    }

    /// The credentials to send, or nil for a public repository. Pasted
    /// tokens and names often bring a stray space or newline, which would
    /// make the header invalid, so those are trimmed; passwords and header
    /// values are sent as typed.
    var credentials: ChekAPI.RepositoryCredentials? {
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return switch kind {
        case .none: nil
        case .token: .bearer(token: trimmed(token))
        case .password: .basic(username: trimmed(username), password: password)
        case .header: .header(name: trimmed(headerName), value: headerValue)
        }
    }
}
