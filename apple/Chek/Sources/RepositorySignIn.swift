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

    /// One header of `.header`, in the order typed.
    struct Header: Equatable, Identifiable, Sendable {
        let id = UUID()
        var name = ""
        var value = ""

        init(name: String = "", value: String = "") {
            self.name = name
            self.value = value
        }
    }

    /// The most headers the server sends.
    static let maxHeaders = 8

    var kind = Kind.none
    var token = ""
    var username = ""
    var password = ""
    var headers = [Header()]

    /// Whether every field the kind needs is filled in.
    var isComplete: Bool {
        switch kind {
        case .none: true
        case .token: !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .password: !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .header:
            !headers.isEmpty && headers.count <= Self.maxHeaders
                && headers.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.isEmpty }
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
        // One header goes as `header`, which every server with private
        // repositories takes; only several need `headers`.
        case .header where headers.count == 1: .header(name: trimmed(headers[0].name), value: headers[0].value)
        case .header: .headers(headers.map { .init(name: trimmed($0.name), value: $0.value) })
        }
    }
}
