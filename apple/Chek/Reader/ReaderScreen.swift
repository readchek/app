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
    /// How far the reader has been pulled down to close it.
    @State private var pull: CGFloat = 0
    @Environment(AppRouter.self) private var router
    @Environment(ReaderSettings.self) private var settings

    init(item: ReadingItem, preferences: ReaderPreferences) {
        _session = State(initialValue: ReaderSession(item: item, preferences: preferences))
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                ZStack {
                    ReaderCanvas(kind: session.item.kind)
                    ReaderContent(session: session, insets: contentInsets)
                    if let chapter = session.item.sourceChapter {
                        NextChapterButton(session: session, chapter: chapter) { next in
                            continueReading(next)
                        }
                    } else {
                        BookEndButton(session: session)
                    }
                    if session.controller.state == .ready {
                        ReadingHint(session: session)
                    }
                }
                // A new chapter is a new page view, not the last one's
                // reused with its old pages.
                .id(session.item.id)
                .readerToolbars(session: session, width: proxy.size.width, openChapter: continueReading)
                // The bars' edge effect darkens the page's top and bottom
                // even with the bars hidden; the page should run clean.
                .scrollEdgeEffectHidden(true, for: .all)
                // The navigation stack paints its own background over the
                // edges otherwise, black in dark mode rather than the page's.
                .containerBackground(for: .navigation) {
                    ReaderCanvas(kind: session.item.kind)
                }
            }
            .onChange(of: proxy.size, initial: true) {
                // Text stays clear of where the controls float, whether or
                // not they're showing, so it never sits under them and never
                // moves when they come and go.
                var insets = Self.deviceInsets(fallback: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
                insets.top += Self.topBarHeight
                insets.bottom += Self.bottomBarHeight
                contentInsets = insets
            }
            .clipShape(.rect(cornerRadius: pull > 0 ? 40 : 0))
            .scaleEffect(1 - min(pull / max(proxy.size.height, 1), 0.4) * 0.3, anchor: .top)
            .offset(y: pull)
            .simultaneousGesture(pullToClose(height: proxy.size.height))
        }
        // The pull-to-close clip and scale act on this frame, so it must be
        // the whole screen or they cut the page off at the safe area.
        .ignoresSafeArea()
        .statusBarHidden(!session.isShowingControls)
        .persistentSystemOverlays(session.isShowingControls ? .automatic : .hidden)
        .readerEffects(session: session)
        .otherDevicePrompt(session: session)
        .readerSignIn(session: session)
        .modifier(ReaderColorScheme(kind: session.item.kind))
        // Reading is looking without touching, which the idle timer takes
        // for inactivity.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // Opens again for the next chapter, which replaces the session.
        .task(id: session.item.id) {
            await session.open()
        }
    }

    /// Goes on to the next chapter in place, without closing the reader.
    private func continueReading(_ item: ReadingItem) {
        let finished = session
        Task { await finished.controller.close() }
        session = ReaderSession(item: item, preferences: settings.preferences(for: item.settingsKey))
    }
}

extension ReaderScreen {
    /// Pulling down from the upper part of the page closes the reader, the
    /// page following the finger and springing back if let go early. Only
    /// the upper part, so it never fights a vertically scrolling comic.
    private func pullToClose(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                guard value.startLocation.y < height * 0.18,
                      value.translation.height > abs(value.translation.width) * 1.5
                else { return }
                // Resistance grows the further it goes, as rubber does.
                let distance = value.translation.height
                pull = distance < 120 ? distance : 120 + (distance - 120) * 0.55
            }
            .onEnded { value in
                guard pull > 0 else { return }
                if pull > 150 || value.predictedEndTranslation.height > height * 0.45 {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    router.closeReader()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        pull = 0
                    }
                }
            }
    }

    /// Room for the floating controls, measured from the glass buttons.
    static let topBarHeight: CGFloat = 36
    static let bottomBarHeight: CGFloat = 40

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
                    // Only text that reflows keeps clear of the screen's
                    // edges; comics and PDFs are pictures and use it all.
                    .padding(session.showsTextSettings ? insets : EdgeInsets())
                    // The margins outside the text are the page too.
                    .background { ReaderCanvas(kind: session.item.kind) }
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
            ReaderFailureView(error: DisplayError(reader: error, kind: session.item.kind), isRetryable: error.isRetryable, session: session)
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
                // iOS draws a determinate circular progress as a spinner,
                // so the ring is drawn here, with the number inside it.
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(fraction, 0.01))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: fraction)
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText(value: fraction))
                }
                .frame(width: 72, height: 72)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Downloading"))
                .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text("Downloading")
                .font(.headline)
            Text("This book opens once it has finished downloading.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReaderFailureView: View {
    let error: DisplayError
    /// Whether the same thing might work next time, as a network failure
    /// might and a damaged file can't.
    var isRetryable = true
    let session: ReaderSession
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(ServerStore.self) private var servers
    @State private var isConfirmingRemoval = false

    /// The server this is read from, when it signed you out, so trying
    /// again can't help and signing in can.
    private var signedOutServer: ServerAccount? {
        guard let id = session.item.ref.server, servers.state(of: id) == .signedOut else { return nil }
        return servers.account(id)
    }

    /// Whether this is a file on the device that can't be read, where
    /// trying again can't help and removing it can.
    private var isDamagedLocalFile: Bool {
        if case .local = session.item.ref, case .source(.file) = session.item.content { return !isRetryable }
        return false
    }

    private var title: String {
        if signedOutServer != nil {
            String(localized: "Signed Out")
        } else if isDamagedLocalFile {
            session.item.kind == .comic ? String(localized: "Can't Open This Comic") : String(localized: "Can't Open This Book")
        } else {
            error.title
        }
    }

    private var description: Text? {
        if let server = signedOutServer {
            Text("Sign in to \(server.name) to keep reading.")
        } else if isDamagedLocalFile {
            Text("The file may be damaged or of a kind Chek doesn't support. Deleting it from Chek doesn't affect the original.")
        } else {
            error.message.map { Text($0) }
        }
    }

    var body: some View {
        EmptyState(verbatim: title, systemImage: signedOutServer == nil ? "book.closed" : "person.crop.circle.badge.xmark", description: description) {
            if isDamagedLocalFile {
                Button("Delete Book", role: .destructive) {
                    isConfirmingRemoval = true
                }
            } else if signedOutServer != nil {
                Button("Sign In") {
                    session.isSigningIn = true
                }
            } else {
                Button("Try Again") {
                    Task { await session.open() }
                }
            }
        } secondary: {
            Button("Close") {
                router.closeReader()
            }
        }
        .confirmationDialog("Delete “\(session.item.title)”?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Delete Book", role: .destructive) {
                if case .local(let id) = session.item.ref, let book = library.book(id) {
                    library.remove(book)
                }
                router.closeReader()
            }
        } message: {
            Text("Its file and reading position are deleted from this device.")
        }
    }
}
