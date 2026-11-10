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
                    ReaderTitle(session: session)
                }
                // Comments are on the chapter's end, where they're read, so
                // the bar keeps to two buttons that never move.
                // How it looks and where to go, always in this order.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Appearance", systemImage: session.showsTextSettings ? "textformat.size" : "slider.horizontal.3") {
                        session.show(.appearance)
                    }
                }
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

/// The controls under the page: a slider through this chapter, with the
/// chapter before and the one after at its ends, as on a music player.
/// Where you are is said once, under the title.
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
                if inSeries {
                    SeriesStepButton(lookup: session.previous, direction: .previous, isChapter: isChapter, opening: opening, open: open)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                ReaderScrubber(session: session)
                    .padding(.horizontal, 16)
                    .frame(height: Self.height)
                    .glassEffect(.regular, in: .capsule)
                if inSeries {
                    SeriesStepButton(lookup: session.next, direction: .next, isChapter: isChapter, opening: opening, open: open)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        }
        // As wide as the screen allows, and no wider than reads well on
        // an iPad.
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    static let height: CGFloat = 44
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

/// The publication's title. A comic's is one line on glass, and while
/// the slider is dragged it gives way to the page under the thumb, so
/// the page being chosen is said without a label of its own. A book's
/// has the chapter you're in under it.
private struct ReaderTitle: View {
    let session: ReaderSession

    var body: some View {
        // Comic pages run under the bar, where plain text would vanish
        // into light artwork, so the title sits on glass like the buttons
        // beside it.
        if session.item.kind == .comic {
            comicLabel
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .glassEffect(.regular, in: .capsule)
        } else {
            bookLabel
        }
    }

    @ViewBuilder private var comicLabel: some View {
        if session.scrubbing != nil {
            PlaceLabel(place: ReaderPlace(session: session).label)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        } else {
            Text(session.item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var bookLabel: some View {
        VStack(spacing: 0) {
            Text(session.item.title)
                .font(.headline)
                .lineLimit(1)
            bookSubtitle
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var bookSubtitle: some View {
        if session.scrubbing != nil {
            PlaceLabel(place: ReaderPlace(session: session).label)
        } else if let chapter = session.controller.location?.title, chapter != session.item.title {
            Text(chapter)
        }
    }
}

/// Where the reader is in what's open, worked out the same way for the
/// slider and for the words under the title.
private struct ReaderPlace {
    let session: ReaderSession

    private var controller: ReaderController { session.controller }

    /// Comics and PDFs have real page numbers. Text that reflows has
    /// positions instead, which aren't pages you'd recognize, so it shows
    /// a percentage.
    var showsPages: Bool {
        guard let format = controller.format else { return false }
        return [.pdf, .cbz, .cbt, .cbr, .cb7].contains(format)
    }

    var count: Int {
        controller.positions?.count ?? 0
    }

    /// The position the reader is at, from 1.
    var position: Double {
        // Reflowing text's last screen can sit on an earlier position than
        // the last, which would leave the thumb short of the end at 100%.
        let isAtEnd = (controller.location?.locations.totalProgression ?? 0) >= ReadingStatus.finishedThreshold
        return isAtEnd && count > 1 ? Double(count) : Double(controller.location?.locations.position ?? 1)
    }

    var label: ScrubberPlace {
        ScrubberPlace.make(
            showsPages: showsPages,
            position: Int(session.scrubbing ?? position),
            count: count,
            progress: progress,
            // Dragging the thumb is choosing a page again.
            isAtChapterEnd: session.shownEdge == .end && session.scrubbing == nil
        )
    }

    private var progress: Double? {
        if let scrubbing = session.scrubbing, count > 1 {
            return (scrubbing - 1) / Double(count - 1)
        }
        return controller.location?.locations.totalProgression
    }
}

/// A slider through the whole publication.
private struct ReaderScrubber: View {
    let session: ReaderSession

    var body: some View {
        let place = ReaderPlace(session: session)
        if place.count > 1 {
            Slider(
                value: Binding(get: { session.scrubbing ?? place.position }, set: { session.scrubbing = $0 }),
                in: 1...Double(place.count),
                step: 1
            ) { editing in
                guard !editing, let target = session.scrubbing else { return }
                Task {
                    await session.controller.go(toPosition: Int(target))
                    session.scrubbing = nil
                }
            }
            .accessibilityLabel(Text("Position"))
        } else {
            ProgressView(value: session.controller.location?.locations.totalProgression ?? 0)
        }
    }
}

private struct PlaceLabel: View {
    let place: ScrubberPlace

    var body: some View {
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
}
