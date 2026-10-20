import SwiftUI

/// Starts the demo: signs in to the demo server and goes to it. One
/// button, shown wherever someone new might look for something to read.
struct TryDemoButton: View {
    var isProminent = false
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @State private var isStarting = false
    @State private var failure: DisplayError?

    var body: some View {
        Button {
            start()
        } label: {
            if isStarting {
                ProgressView()
            } else {
                Label("Try the Demo", systemImage: "sparkles")
            }
        }
        .disabled(isStarting)
        .alert(
            failure?.title ?? "",
            isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }
        ) {
            Button("OK") {}
        } message: {
            if let message = failure?.message {
                Text(message)
            }
        }
    }

    private func start() {
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                try await servers.startDemo()
                // Straight to the demo server, where every kind of
                // publication is a tap away.
                router.sheet = nil
                router.tab = .browse
                router.browsePath = [.server(DemoMode.accountID)]
            } catch {
                let reason = DisplayError(error)
                failure = DisplayError(
                    title: String(localized: "Couldn't start the demo."),
                    message: reason.message ?? reason.title
                )
            }
        }
    }
}

extension View {
    /// A banner under the navigation bar while the demo is connected,
    /// saying so and offering the way out. Goes on every screen's content,
    /// since the demo should never be mistaken for the real thing a few
    /// taps in. The demo ends on its own at the next launch.
    func demoBanner() -> some View {
        modifier(DemoBanner())
    }
}

private struct DemoBanner: ViewModifier {
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if servers.isDemo {
                // One word, out of the way, with the way out a tap away.
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("Demo")
                        .font(.caption.weight(.semibold))
                    Button("Exit", systemImage: "xmark") {
                        Task {
                            await servers.endDemo()
                            router.serverRemoved(DemoMode.accountID)
                            router.homePath = []
                            router.searchPath = []
                        }
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Exit the demo"))
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .foregroundStyle(.primary)
                .background(.yellow.opacity(0.35), in: .capsule)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, Metrics.margin)
                .padding(.bottom, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: servers.isDemo)
    }
}
