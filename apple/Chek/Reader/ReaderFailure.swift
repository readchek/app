import ChekReader
import Foundation

extension DisplayError {
    /// What to tell the reader when the engine couldn't open `kind` of
    /// publication. The engine's own messages are written for developers
    /// and nest each layer's reason, so they're turned into a short title
    /// and the one reason that matters.
    init(reader error: ReaderError, kind: PublicationKind) {
        let what = kind == .comic ? String(localized: "this comic") : String(localized: "this book")
        switch error {
        case .network(let reason):
            self.init(
                title: String(localized: "Couldn't load \(what)."),
                message: Self.innermostReason(reason) ?? String(localized: "Check your connection and try again.")
            )
        case .unsupportedFormat, .formatNotIncluded, .notYetImplemented:
            self.init(
                title: String(localized: "Chek can't read \(what)."),
                message: String(localized: "It's a kind of file Chek doesn't open.")
            )
        case .drmProtected:
            self.init(
                title: String(localized: "Chek can't read \(what)."),
                message: String(localized: "It's copy-protected by the store it came from, so only that store's app can open it.")
            )
        case .malformed(let reason):
            self.init(
                title: String(localized: "Couldn't open \(what)."),
                message: Self.innermostReason(reason) ?? String(localized: "It may be damaged."))
        case .limitExceeded:
            self.init(
                title: String(localized: "Couldn't open \(what)."),
                message: String(localized: "It's too large to open on this device.")
            )
        case .cancelled:
            self.init(title: String(localized: "Opening stopped."))
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
