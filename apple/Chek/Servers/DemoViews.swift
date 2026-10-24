import SwiftUI

/// Starts the demo: signs in to the demo server and goes to it. One
/// button, shown wherever someone new might look for something to read.
struct TryDemoButton: View {
    @State private var isOpening = false

    var body: some View {
        Button {
            isOpening = true
        } label: {
            if isOpening {
                ProgressView()
            } else {
                Label("Open Sample Library", systemImage: "sparkles")
            }
        }
        .disabled(isOpening)
        .sampleLibraryOpener(isOpening: $isOpening)
    }
}

extension View {
    /// Opens the sample library when `isOpening` turns true, as a button
    /// or a link in an empty state's sentence asks, and goes to it, saying
    /// so if it can't. `isOpening` turns false again once it's done.
    func sampleLibraryOpener(isOpening: Binding<Bool>) -> some View {
        modifier(SampleLibraryOpener(isOpening: isOpening))
    }
}

private struct SampleLibraryOpener: ViewModifier {
    @Binding var isOpening: Bool
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @State private var failure: DisplayError?

    func body(content: Content) -> some View {
        content
            .task(id: isOpening) {
                guard isOpening else { return }
                defer { isOpening = false }
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
                        title: String(localized: "Couldn't Open Sample Library"),
                        message: reason.message ?? reason.title
                    )
                }
            }
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
}

extension View {
    /// A banner under the navigation bar while the demo is connected,
    /// saying so. Goes on every screen's content, since the demo should
    /// never be mistaken for the real thing a few taps in. The demo ends
    /// on its own at the next launch.
    func demoBanner() -> some View {
        modifier(DemoBanner())
    }
}

private struct DemoBanner: ViewModifier {
    @Environment(ServerStore.self) private var servers

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if servers.isDemo {
                // Small, quiet and out of the way: a label, not a control.
                // Closing the sample is in the library's More menu and in
                // Settings, where every other library action is.
                Label("Sample Library", systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.fill.tertiary, in: .capsule)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Metrics.margin)
                    .padding(.bottom, 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: servers.isDemo)
    }
}
