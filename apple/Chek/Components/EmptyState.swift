import SwiftUI

/// The one look for a screen, or part of one, with nothing to show: a
/// symbol and a sentence on why and what to do. There's no title, since
/// the screen's own title already says where you are.
///
/// What you can do is part of the sentence, as links, rather than buttons
/// under it: "[Add books](chek-action://add) and comics from Files…". Each
/// link's host names its entry in `actions`.
struct EmptyState: View {
    private let systemImage: String
    private let message: Text
    private let actions: [String: () -> Void]

    init(systemImage: String, message: Text, actions: [String: () -> Void] = [:]) {
        self.systemImage = systemImage
        self.message = message
        self.actions = actions
    }

    /// `message` is Markdown, so its links can name actions.
    init(_ message: LocalizedStringKey, systemImage: String, actions: [String: () -> Void] = [:]) {
        self.init(systemImage: systemImage, message: Text(message), actions: actions)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            message
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == EmptyState.scheme, let action = actions[url.host() ?? ""] else { return .systemAction }
            action()
            return .handled
        })
    }

    static let scheme = "chek-action"

    /// A link in a message that runs the action named `name`.
    static func link(_ name: String) -> URL {
        URL(string: "\(scheme)://\(name)")!
    }
}

/// A load that failed, said the same way on every screen: what to do
/// about it, with "try again" as a link when trying again can help.
struct FailureState: View {
    let error: DisplayError
    var retry: (() async -> Void)?

    var body: some View {
        EmptyState(systemImage: "wifi.exclamationmark", message: Text(message), actions: [
            "retry": { Task { await retry?() } },
        ])
    }

    /// The error's explanation, else its title, with "try again" linked:
    /// the words already in it when it says so, else added at the end.
    private var message: AttributedString {
        var text = AttributedString(error.message ?? error.title)
        guard retry != nil else { return text }
        if let range = text.range(of: String(localized: "try again"), options: .caseInsensitive) {
            text[range].link = EmptyState.link("retry")
        } else {
            var link = AttributedString(String(localized: "Try Again"))
            link.link = EmptyState.link("retry")
            text += AttributedString(" ") + link
        }
        return text
    }
}
