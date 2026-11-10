import ChekReader
import Foundation

extension DisplayError {
    /// What to tell the reader when the engine couldn't open `kind` of
    /// publication. The engine's own messages are written for developers
    /// and nest each layer's reason, so they're turned into a short title
    /// and the one reason that matters.
    init(reader error: ReaderError, kind: PublicationKind) {
        // Titles are title-case fragments, so the noun is capitalized too.
        let what = kind == .comic ? String(localized: "This Comic") : String(localized: "This Book")
        switch error {
        case .network(let reason):
            self.init(
                title: String(localized: "Couldn't Load \(what)"),
                message: Self.innermostReason(reason) ?? String(localized: "Check your internet connection and try again."),
                kind: .connection
            )
        case .unsupportedFormat, .formatNotIncluded, .notYetImplemented:
            self.init(
                title: String(localized: "Can't Open \(what)"),
                message: String(localized: "Chek doesn't support this kind of file.")
            )
        case .drmProtected:
            self.init(
                title: String(localized: "Can't Open \(what)"),
                message: String(localized: "It's copy-protected and can be opened only in the app it was bought from.")
            )
        case .malformed(let reason):
            self.init(
                title: String(localized: "Couldn't Open \(what)"),
                message: Self.innermostReason(reason) ?? String(localized: "The file may be damaged."))
        case .limitExceeded:
            self.init(
                title: String(localized: "Couldn't Open \(what)"),
                message: String(localized: "It's too large to open on this device.")
            )
        case .cancelled:
            self.init(title: String(localized: "Opening Stopped"))
        }
    }

    /// The last reason in a chain such as "A failed: B failed: C", which
    /// is the one closest to what went wrong, and the only one worth
    /// showing.
    private static func innermostReason(_ reason: String) -> String? {
        let last = reason.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return last.isEmpty ? nil : last
    }
}

/// The sentence on the reader's failure page: what went wrong, then the
/// ways out as links. Trying again is offered once, and only when it can
/// help; closing always is.
enum ReaderFailureMessage {
    static func make(for error: DisplayError, kind: PublicationKind, canRetry: Bool) -> AttributedString {
        let retries = canRetry && error.canRetry
        var text = FailureState.message(for: error, canRetry: retries)
        let close: AttributedString = switch (kind, retries) {
        case (.comic, true): AttributedString(localized: "You can also [close](chek-action://close) this comic.")
        case (.book, true): AttributedString(localized: "You can also [close](chek-action://close) this book.")
        case (.comic, false): AttributedString(localized: "[Close](chek-action://close) this comic.")
        case (.book, false): AttributedString(localized: "[Close](chek-action://close) this book.")
        }
        text += AttributedString(" ") + close
        return text
    }
}
