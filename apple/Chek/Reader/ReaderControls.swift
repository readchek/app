import ChekReader
import SwiftUI

extension View {
    /// The reader's toolbars, shown and hidden together.
    func readerToolbars(session: ReaderSession, opening: ReadingTarget?, open: @escaping (ReadingTarget) -> Void) -> some View {
        modifier(ReaderToolbars(session: session, opening: opening, open: open))
    }
}

private struct ReaderToolbars: ViewModifier {
    let session: ReaderSession
    /// What's being got ready to open, if anything.
    let opening: ReadingTarget?
    /// Opens another chapter or volume of the same series in place.
    let open: (ReadingTarget) -> Void
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        router.closeReader()
                    }
                }
                ToolbarItem(placement: .principal) {
                    ReaderTitle(title: session.item.title, controller: session.controller, isOverArtwork: session.item.kind == .comic)
                }
                // Comments sit beside the contents, and only on a chapter
                // that has some, so every other book keeps one button
                // either side of the title.
                if let comments = session.comments, comments.count != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        CommentsButton(comments: comments) {
                            session.show(.comments)
                        }
                    }
                }
                // One button either side, so the title sits in the visual
                // middle, not just the measured one. Appearance goes with
                // the scrubber in ``ReaderBottomBar``, as in Books.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Contents", systemImage: "list.bullet") {
                        session.show(.contents)
                    }
                    .disabled(session.controller.state != .ready)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Only the glass controls float over the page; the bars
            // themselves draw nothing, so no band of another color shows.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)

            // Contents and the scrubber need an open publication; while
            // there isn't one, only Close is of any use.
            .toolbarVisibility(session.isShowingControls ? .visible : .hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if session.isShowingControls, session.controller.state == .ready {
                    ReaderBottomBar(session: session, opening: opening, open: open)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: session.isShowingControls)
            .sheet(item: Bindable(session).panel) { panel in
                switch panel {
                case .contents:
                    // A book from a source has its own contents, which say
                    // more than the source's one chapter for it.
                    if let chapter = session.item.sourceChapter, session.item.kind == .comic {
                        ChaptersPanel(session: session, chapter: chapter, open: open)
                    } else {
                        ContentsPanel(session: session)
                    }
                case .comments:
                    if let comments = session.comments {
                        CommentsPanel(comments: comments)
                    }
                case .appearance:
                    AppearancePanel(
                        showsTextSettings: session.showsTextSettings,
                        showsCommentSettings: session.item.sourceChapter != nil,
                        // Only pictures have a layout to get wrong; text
                        // follows its language.
                        modeKey: session.showsTextSettings ? nil : session.item.settingsKey
                    )
                }
            }
    }
}

/// The controls under the page: the chapter before, your place in this
/// one, the chapter after, and appearance, always in that order.
///
/// It's drawn here rather than given to the system's bottom toolbar,
/// which moves whatever it finds no room for into a menu. Next Chapter
/// went there on some phones, and a control that moves can't be found
/// without looking.
private struct ReaderBottomBar: View {
    let session: ReaderSession
    let opening: ReadingTarget?
    let open: (ReadingTarget) -> Void

    var body: some View {
        let inSeries = session.item.series != nil
        let isChapter = session.item.sourceChapter != nil
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    if inSeries {
                        SeriesStepButton(lookup: session.previous, direction: .previous, isChapter: isChapter, opening: opening, open: open)
                    }
                    ReaderScrubber(controller: session.controller, isAtChapterEnd: session.shownEdge == .end)
                        .padding(.horizontal, inSeries ? 0 : 12)
                    if inSeries {
                        SeriesStepButton(lookup: session.next, direction: .next, isChapter: isChapter, opening: opening, open: open)
                    }
                }
                .frame(height: Self.height)
                .glassEffect(.regular.interactive(), in: .capsule)
                Button("Appearance", systemImage: session.showsTextSettings ? "textformat.size" : "slider.horizontal.3") {
                    session.show(.appearance)
                }
                .modifier(BarButton())
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        // As wide as the screen allows, and no wider than reads well on
        // an iPad.
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    static let height: CGFloat = 48
}

/// A button in ``ReaderBottomBar``: its symbol alone, on a target big
/// enough for a thumb.
private struct BarButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .buttonStyle(.borderless)
            .frame(width: ReaderBottomBar.height, height: ReaderBottomBar.height)
            .contentShape(.rect)
    }
}

/// Goes to the chapter or volume before or after this one. Disabled
/// while it's looked up and at either end of the series.
private struct SeriesStepButton: View {
    enum Direction {
        case previous, next
    }

    let lookup: NeighborLookup
    let direction: Direction
    /// Whether the series is in chapters rather than volumes or books.
    let isChapter: Bool
    let opening: ReadingTarget?
    let open: (ReadingTarget) -> Void

    var body: some View {
        Button {
            if let target = lookup.target {
                open(target)
            }
        } label: {
            Label {
                title
            } icon: {
                if let opening, opening == lookup.target {
                    ProgressView()
                } else {
                    Image(systemName: direction == .previous ? "backward.end.fill" : "forward.end.fill")
                }
            }
        }
        .disabled(lookup.target == nil || opening != nil)
        .modifier(BarButton())
        .accessibilityValue(lookup.target.map { Text($0.title) } ?? Text(""))
    }

    private var title: Text {
        switch (direction, isChapter) {
        case (.previous, true): Text("Previous Chapter")
        case (.next, true): Text("Next Chapter")
        case (.previous, false): Text("Previous in Series")
        case (.next, false): Text("Next in Series")
        }
    }
}

/// The publication's title, with the chapter you're in under it.
private struct ReaderTitle: View {
    let title: String
    let controller: ReaderController
    /// Comic pages run under the bar, where plain text would vanish into
    /// light artwork, so the title sits on glass like the buttons beside it.
    let isOverArtwork: Bool

    var body: some View {
        if isOverArtwork {
            label
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        } else {
            label
        }
    }

    private var label: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if let chapter = controller.location?.title, chapter != title {
                Text(chapter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slider through the whole publication, with where you are beside it.
private struct ReaderScrubber: View {
    let controller: ReaderController
    /// Whether the chapter end shows, past the last page.
    let isAtChapterEnd: Bool
    /// Where the slider is while you drag it, before the reader moves.
    @State private var scrubbing: Double?

    /// Comics and PDFs have real page numbers. Text that reflows has
    /// positions instead, which aren't pages you'd recognize, so it shows
    /// a percentage.
    private var showsPages: Bool {
        guard let format = controller.format else { return false }
        return [.pdf, .cbz, .cbt, .cbr, .cb7].contains(format)
    }

    var body: some View {
        let count = controller.positions?.count ?? 0
        // Reflowing text's last screen can sit on an earlier position than
        // the last, which would leave the thumb short of the end at 100%.
        let isAtEnd = (controller.location?.locations.totalProgression ?? 0) >= ReadingStatus.finishedThreshold
        let position = isAtEnd && count > 1 ? Double(count) : Double(controller.location?.locations.position ?? 1)
        HStack(spacing: 12) {
            if count > 1 {
                Slider(
                    value: Binding(get: { scrubbing ?? position }, set: { scrubbing = $0 }),
                    in: 1...Double(count),
                    step: 1
                ) { editing in
                    guard !editing, let target = scrubbing else { return }
                    Task {
                        await controller.go(toPosition: Int(target))
                        scrubbing = nil
                    }
                }
                .accessibilityLabel(Text("Position"))
            } else {
                ProgressView(value: controller.location?.locations.totalProgression ?? 0)
            }
            PlaceLabel(place: ScrubberPlace.make(
                showsPages: showsPages,
                position: Int(scrubbing ?? position),
                count: count,
                progress: progress(count: count),
                // Dragging the thumb is choosing a page again.
                isAtChapterEnd: isAtChapterEnd && scrubbing == nil
            ))
        }
        .padding(.horizontal, 8)
    }

    private func progress(count: Int) -> Double? {
        if let scrubbing, count > 1 {
            return (scrubbing - 1) / Double(count - 1)
        }
        return controller.location?.locations.totalProgression
    }
}

private struct PlaceLabel: View {
    let place: ScrubberPlace

    var body: some View {
        Group {
            switch place {
            case .page(let position, let count):
                Text("\(position) of \(count)")
            case .progress(let progress):
                Text(progress, format: .percent.precision(.fractionLength(0)))
            case .finished:
                Text("Finished")
            case .none:
                EmptyView()
            }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .fixedSize()
    }
}
