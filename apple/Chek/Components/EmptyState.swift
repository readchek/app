import SwiftUI

/// The one look for a screen, or part of one, with nothing to show: an
/// icon, a title, a line on why and what to do, then its actions.
///
/// It has at most one action that matters, the only prominent button.
/// Anything else is a quiet link under it, so a screen never offers
/// several equal choices.
struct EmptyState<Action: View, Secondary: View>: View {
    private let title: Text
    private let systemImage: String
    private let description: Text?
    private let action: Action
    private let secondary: Secondary

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil,
        @ViewBuilder action: () -> Action,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.description = description
        self.action = action()
        self.secondary = secondary()
    }

    /// For titles that are already localized, such as an error's.
    init(
        verbatim title: String,
        systemImage: String,
        description: Text? = nil,
        @ViewBuilder action: () -> Action,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.description = description
        self.action = action()
        self.secondary = secondary()
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            if let description {
                description
            }
        } actions: {
            VStack(spacing: 20) {
                // Styled here rather than by the caller, so every screen's
                // main action looks the same.
                action
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                VStack(spacing: 6) {
                    secondary
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleOnly)
                .font(.subheadline)
            }
        }
    }
}

extension EmptyState where Secondary == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil, @ViewBuilder action: () -> Action) {
        self.init(title, systemImage: systemImage, description: description, action: action) { EmptyView() }
    }

    init(verbatim title: String, systemImage: String, description: Text? = nil, @ViewBuilder action: () -> Action) {
        self.init(verbatim: title, systemImage: systemImage, description: description, action: action) { EmptyView() }
    }
}

extension EmptyState where Action == EmptyView, Secondary == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }

    init(verbatim title: String, systemImage: String, description: Text? = nil) {
        self.init(verbatim: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

/// A load that failed, said the same way on every screen, with the way to
/// try again when there is one.
struct FailureState: View {
    let error: DisplayError
    var retry: (() async -> Void)?

    var body: some View {
        EmptyState(verbatim: error.title, systemImage: "wifi.exclamationmark", description: error.message.map { Text($0) }) {
            if let retry {
                Button("Try Again") {
                    Task { await retry() }
                }
            }
        }
    }
}
