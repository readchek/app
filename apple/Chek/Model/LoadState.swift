import Foundation

/// The phase of something loaded once, such as a server's libraries.
///
/// One enum instead of separate loading, error and value properties, so
/// the three can never disagree.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(DisplayError)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

extension LoadState: Equatable where Value: Equatable {}

/// An error ready to show: a title and an optional explanation, already
/// written for people rather than developers.
struct DisplayError: Error, Hashable, Sendable {
    /// What went wrong, as far as it changes what's shown: the symbol, and
    /// whether trying again is worth offering.
    enum Kind: Hashable, Sendable {
        /// The connection or the server, which may work next time.
        case connection
        /// The session ended; signing in is what helps.
        case signedOut
        /// It isn't there any more, so trying again can't help.
        case gone
        case other
    }

    var title: String
    var message: String?
    var kind = Kind.other

    init(title: String, message: String? = nil, kind: Kind = .other) {
        self.title = title
        self.message = message
        self.kind = kind
    }

    init(_ error: any Error) {
        if let error = error as? DisplayError {
            self = error
        } else if let error = error as? ChekError {
            self.init(title: error.errorDescription ?? error.localizedDescription, message: error.recoverySuggestion, kind: Kind(error))
        } else if let error = error as? LocalizedError {
            self.init(title: error.errorDescription ?? error.localizedDescription, message: error.recoverySuggestion)
        } else {
            self.init(title: error.localizedDescription)
        }
    }

    /// Whether the same thing might work on another try.
    var canRetry: Bool { kind != .gone }

    /// The symbol that stands for this failure.
    var systemImage: String {
        switch kind {
        case .connection: "wifi.exclamationmark"
        case .signedOut: "person.crop.circle.badge.exclamationmark"
        case .gone: "questionmark.folder"
        case .other: "exclamationmark.circle"
        }
    }

    /// What went wrong as one whole sentence, to go in front of others:
    /// the explanation, or the title with a full stop when that's all
    /// there is.
    var sentence: String {
        let text = (message ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}

extension DisplayError.Kind {
    init(_ error: ChekError) {
        self = switch error {
        case .offline: .connection
        case .unauthorized: .signedOut
        case .notFound, .server(_, "source_unavailable"): .gone
        case .progressConflict, .server, .invalidResponse: .other
        }
    }
}

extension DisplayError: LocalizedError {
    var errorDescription: String? { title }
    var recoverySuggestion: String? { message }
}
