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
    /// The chapter or volume being got ready to read next, if any.
    @State private var opening: ReadingTarget?
    /// What the chapter end shows while the next chapter opens. It stays up
    /// across the switch to the new chapter until its page is ready, so
    /// there's no blank screen in between.
    @State private var handoff: ChapterHandoff?
    /// Why it couldn't be opened, until that's been seen.
    @State private var openingFailure: DisplayError?
    @Environment(AppRouter.self) private var router
    @Environment(ReaderSettings.self) private var settings
    @Environment(ServerSync.self) private var sync
    @Environment(LibraryStore.self) private var library
    @Environment(ProgressStore.self) private var progress
    @Environment(ServerStore.self) private var servers

    init(item: ReadingItem, preferences: ReaderPreferences) {
        _session = State(initialValue: ReaderSession(item: item, preferences: preferences))
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                ZStack {
                    ReaderCanvas(kind: session.item.kind)
                    ReaderContent(session: session, insets: contentInsets)
                        // Where the reader turns pages, the chapter's ends
                        // are pages among them.
                        .readerEdgePages(start: session.edgePages.start, end: session.edgePages.end) { [session, settings, finder] edge in
                            ChapterEdge(session: session, edge: edge, finder: finder)
                                .environment(settings)
                        }
                    if session.item.kind == .comic {
                        ControlsScrim(isShowing: session.isShowingControls)
                    }
                    Group {
                        if let handoff {
                            ChapterEndPage(kind: session.item.kind, next: .found(handoff.target), isNext: handoff.isNext, isOpening: true, retry: findNeighbors)
                        } else if session.edge == .end {
                            ChapterEndPage(kind: session.item.kind, next: session.next, isOpening: false, retry: findNeighbors, comments: session.comments, showComments: { session.show(.comments) }, turns: session.turns) { forward in
                                if forward, let target = session.next.target {
                                    open(target)
                                } else if !forward {
                                    session.leaveEdge()
                                }
                            } tapMiddle: {
                                session.toggleControls()
                            }
                        } else if session.edge == .start {
                            ChapterEndPage(kind: session.item.kind, next: session.previous, isNext: false, isOpening: false, retry: findNeighbors, turns: session.turns) { forward in
                                if forward {
                                    session.leaveEdge()
                                } else if let target = session.previous.target {
                                    open(target)
                                }
                            } tapMiddle: {
                                session.toggleControls()
                            }
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: session.edge)
                    if session.controller.state == .ready {
                        ReadingHint(session: session)
                    }
                }
                // A new chapter is a new page view, not the last one's
                // reused with its old pages.
                .id(session.item.id)
                .readerToolbars(session: session, opening: opening, open: open)
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
            await session.openIfNeeded()
        }
        // Alongside opening, so the way on is known before the last page.
        .task(id: session.item.id) {
            await session.findNeighbors(with: finder)
        }
        // Whether the chapter has comments, so their button is ready with
        // the page. Turning comments off takes it away and asks nothing.
        .task(id: CommentsLookup(item: session.item.id, isOn: settings.showsComments)) {
            guard settings.showsComments, let chapter = session.item.sourceChapter else {
                session.comments = nil
                return
            }
            let comments = ChapterComments(chapter: chapter, servers: servers)
            session.comments = comments
            await comments.look()
        }
        // A turn past the last page goes on to what's next.
        .onChange(of: session.controller.turnsPastEnd) {
            if let target = session.turnedPastEnd() {
                open(target)
            }
        }
        // And one back past the first page goes to what came before.
        .onChange(of: session.controller.turnsPastStart) {
            if let target = session.turnedPastStart() {
                open(target)
            }
        }
        .onChange(of: isSettled) {
            if isSettled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    handoff = nil
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.item.id)
        .alert(
            openingFailure?.title ?? "",
            isPresented: Binding(get: { openingFailure != nil }, set: { if !$0 { openingFailure = nil } }),
            presenting: openingFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            if let message = failure.message {
                Text(message)
            }
        }
    }

    private var finder: NeighborFinder {
        NeighborFinder(sync: sync, library: library, progress: progress)
    }

    private func findNeighbors() {
        Task { await session.findNeighbors(with: finder) }
    }

    /// Whether the open chapter is showing, or showing why it can't be, so
    /// the chapter end that covered the switch to it can go.
    private var isSettled: Bool {
        guard session.phase == .reading else { return true }
        switch session.controller.state {
        case .ready, .failed: return true
        case .idle, .opening, .closing, .closed: return false
        }
    }

    /// Gets `target` ready and goes on to it in place. A second tap while
    /// one is opening is ignored.
    private func open(_ target: ReadingTarget) {
        guard opening == nil else { return }
        opening = target
        let isNext = target == session.next.target
        // Turned back into from its first page, the chapter before opens
        // on its last, where reading back left off.
        let fromEnd = !isNext && session.shownEdge == .start
        // Turned onto the page past the end, which is already showing what
        // the switch shows, so it's taken over without a fade.
        // Turned onto or past one of the chapter's own pages in the reader,
        // which stays on screen while the next one opens behind it, so the
        // switch is straight to its page.
        let isTurnedOnto = session.controller.edge != nil
        if isTurnedOnto {
            session.isOpeningNeighbor = true
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                handoff = ChapterHandoff(target: target, isNext: isNext)
            }
        }
        Task {
            defer { opening = nil }
            do {
                let item = try await finder.readingItem(for: target, fromEnd: fromEnd)
                let next = ReaderSession(item: item, preferences: settings.preferences(for: item.settingsKey))
                if isTurnedOnto {
                    await next.open()
                }
                continueReading(next)
            } catch {
                handoff = nil
                session.isOpeningNeighbor = false
                openingFailure = DisplayError(error)
                // Off the page past the end, which only waits for it, and
                // back to the chapter's end.
                if session.controller.edge != nil {
                    await session.controller.goBackward()
                }
            }
        }
    }

    /// Goes on to another chapter in place, without closing the reader.
    private func continueReading(_ next: ReaderSession) {
        let finished = session
        Task { await finished.controller.close() }
        session = next
    }
}

/// What the comments are looked up for: the chapter, and whether they're on.
private struct CommentsLookup: Equatable {
    var item: PublicationRef
    var isOn: Bool
}

/// What's on the chapter end while the next chapter opens.
private struct ChapterHandoff: Equatable {
    var target: ReadingTarget
    /// Whether it's the next chapter, rather than the previous one.
    var isNext: Bool
}

/// An end of the chapter as one of the reader's pages: the chapter it
/// leads to, turned onto and away from as the pages are.
private struct ChapterEdge: View {
    let session: ReaderSession
    let edge: ReaderEdge
    let finder: NeighborFinder

    var body: some View {
        ChapterEndPage(
            kind: session.item.kind,
            next: edge == .end ? session.next : session.previous,
            isNext: edge == .end,
            isOpening: session.isOpeningNeighbor,
            retry: { Task { await session.findNeighbors(with: finder) } },
            comments: edge == .end ? session.comments : nil,
            showComments: { session.show(.comments) },
            turns: session.turns,
            followsSwipes: false
        ) { forward in
            Task {
                if forward {
                    await session.controller.goForward()
                } else {
                    await session.controller.goBackward()
                }
            }
        } tapMiddle: {
            session.toggleControls()
        }
    }
}

extension ReaderSession {
    /// Which way this publication's pages turn, for the chapter's ends to
    /// turn the same way.
    var turns: ChapterEndPage.Turns {
        controller.publication?.metadata.readingProgression == .rightToLeft ? .rightToLeft : .leftToRight
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

/// A shade at the top and bottom of a comic while the controls show.
/// Comics read in dark mode, and over a white page the glass bars, the
/// page count and the status bar's white text all wash out without it.
private struct ControlsScrim: View {
    let isShowing: Bool

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .opacity(isShowing ? 1 : 0)
        .animation(.smooth(duration: 0.25), value: isShowing)
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

    /// What went wrong and what to do, with the way out as links.
    private var message: Text {
        let isComic = session.item.kind == .comic
        if let server = signedOutServer {
            if isComic {
                return Text("[Sign in](chek-action://signin) to \(server.name) to keep reading, or [close](chek-action://close) this comic.")
            } else {
                return Text("[Sign in](chek-action://signin) to \(server.name) to keep reading, or [close](chek-action://close) this book.")
            }
        } else if isDamagedLocalFile {
            return Text("The file may be damaged or of a kind Chek doesn't support. You can [delete it](chek-action://delete) from Chek without affecting the original, or [close](chek-action://close) it.")
        } else {
            return Text(ReaderFailureMessage.make(for: error, kind: session.item.kind, canRetry: isRetryable))
        }
    }

    var body: some View {
        EmptyState(systemImage: signedOutServer == nil ? "book.closed" : "person.crop.circle.badge.exclamationmark", message: message, actions: [
            "signin": { session.isSigningIn = true },
            "delete": { isConfirmingRemoval = true },
            "retry": { Task { await session.open() } },
            "close": { router.closeReader() },
        ])
        .confirmationDialog("Delete “\(session.item.title)”?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
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
