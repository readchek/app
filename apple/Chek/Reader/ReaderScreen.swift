import ChekReader
import SwiftUI

/// Reads one publication full screen, with Liquid Glass controls that
/// appear when you tap the middle of the page.
struct ReaderScreen: View {
    @State private var session: ReaderSession

    init(item: ReadingItem, preferences: ReaderPreferences) {
        _session = State(initialValue: ReaderSession(item: item, preferences: preferences))
    }

    var body: some View {
        ZStack {
            ReaderCanvas(kind: session.item.kind)
            ReaderContent(session: session)
            ReaderControls(session: session)
        }
        .statusBarHidden(!session.isShowingControls)
        .persistentSystemOverlays(session.isShowingControls ? .automatic : .hidden)
        .animation(.smooth(duration: 0.25), value: session.isShowingControls)
        .readerEffects(session: session)
        .modifier(ReaderColorScheme(kind: session.item.kind))
        .task {
            await session.open()
        }
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

    var body: some View {
        switch session.phase {
        case .downloading(let fraction):
            ReaderDownloadView(fraction: fraction)
        case .failed(let error):
            ReaderFailureView(error: error, session: session)
        case .reading:
            ZStack {
                NavigatorView(controller: session.controller)
                    .ignoresSafeArea(edges: session.item.kind == .comic ? .all : [])
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
            .buttonStyle(.glassProminent)
            Button("Close") {
                router.closeReader()
            }
            .buttonStyle(.glass)
        }
    }
}
