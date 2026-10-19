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
}

extension LoadState: Equatable where Value: Equatable {}

/// An error ready to show: a title and an optional explanation, already
/// written for people rather than developers.
struct DisplayError: Error, Hashable, Sendable {
    var title: String
    var message: String?

    init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }

    init(_ error: any Error) {
        if let error = error as? DisplayError {
            self = error
        } else if let error = error as? LocalizedError {
            self.init(title: error.errorDescription ?? error.localizedDescription, message: error.recoverySuggestion)
        } else {
            self.init(title: error.localizedDescription)
        }
    }
}

extension DisplayError: LocalizedError {
    var errorDescription: String? { title }
    var recoverySuggestion: String? { message }
}
