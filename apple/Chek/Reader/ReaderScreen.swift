import ChekReader
import SwiftUI

/// Reads one publication full screen. Tapping the middle of the page
/// shows the toolbars: close, title, contents and appearance at the top,
/// and your place in the book at the bottom.
struct ReaderScreen: View {
    @State private var session: ReaderSession
    /// Where the page's content sits, worked out once per screen size so
    /// showing and hiding the controls or the status bar never moves it.
    @State private var contentInsets = EdgeInsets()

    init(item: ReadingItem, preferences: ReaderPreferences) {
        _session = State(initialValue: ReaderSession(item: item, preferences: preferences))
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                ZStack {
                    ReaderCanvas(kind: session.item.kind)
                    ReaderContent(session: session, insets: contentInsets)
                }
                .readerToolbars(session: session, width: proxy.size.width)
            }
            .onChange(of: proxy.size, initial: true) {
                contentInsets = Self.deviceInsets(fallback: proxy.safeAreaInsets)
            }
        }
        .statusBarHidden(!session.isShowingControls)
        .persistentSystemOverlays(session.isShowingControls ? .automatic : .hidden)
        .readerEffects(session: session)
        .otherDevicePrompt(session: session)
        .modifier(ReaderColorScheme(kind: session.item.kind))
        .task {
            await session.open()
        }
    }
}

extension ReaderScreen {
    /// The screen's own insets, for the sensor housing and the home
    /// indicator, which don't change when bars come and go.
    static func deviceInsets(fallback: EdgeInsets) -> EdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let insets = window?.safeAreaInsets else { return fallback }
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}

/// Light or dark to match the page, for the controls, panels and status
/// bar alike.
private struct ReaderColorScheme: ViewModifier {
    let kind: PublicationKind
    @Environment(ReaderSettings.self) private var settings

    func body(content: Content) -> some View {
        content.preferredColorScheme(kind == .comic ? .dark : ReaderTheme(settings.theme).colorScheme)
    }
}

/// The color behind the page, matched to the reading theme so the edges
/// around the text don't show a different color.
private struct ReaderCanvas: View {
    let kind: PublicationKind
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        Group {
            switch kind {
            case .comic: Color.black
            case .book: ReaderTheme(settings.theme).background
            }
        }
        .ignoresSafeArea()
    }
}

/// The page, or what's in its place while it downloads, opens or fails.
private struct ReaderContent: View {
    let session: ReaderSession
    /// The device's safe area. Text stays inside it; comics use the whole
    /// screen.
    let insets: EdgeInsets

    var body: some View {
        switch session.phase {
        case .downloading(let fraction):
            ReaderDownloadView(fraction: fraction)
        case .failed(let error):
            ReaderFailureView(error: error, session: session)
        case .reading:
            ZStack {
                NavigatorView(controller: session.controller)
                    .padding(session.item.kind == .comic ? EdgeInsets() : insets)
                    .ignoresSafeArea()
                ReaderStateView(session: session)
            }
        }
    }
}

/// Loading and failure states of the reader engine.
private struct ReaderStateView: View {
    let session: ReaderSession

    var body: some View {
        switch session.controller.state {
        case .idle, .opening:
            ProgressView()
                .controlSize(.large)
        case .failed(let error):
            ReaderFailureView(error: DisplayError(error), session: session)
        case .ready, .closing, .closed:
            EmptyView()
        }
    }
}

private struct ReaderDownloadView: View {
    let fraction: Double?

    var body: some View {
        VStack(spacing: 16) {
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text("Downloading")
                .font(.headline)
        }
    }
}

private struct ReaderFailureView: View {
    let error: DisplayError
    let session: ReaderSession
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "book.closed")
        } description: {
            if let message = error.message {
                Text(message)
            }
        } actions: {
            Button("Try Again") {
                Task { await session.open() }
            }
            .buttonStyle(.borderedProminent)
            Button("Close") {
                router.closeReader()
            }
        }
    }
}
