import ChekReader
import SwiftUI

extension View {
    /// The reader's toolbars, shown and hidden together.
    func readerToolbars(session: ReaderSession, width: CGFloat, opening: ReadingTarget?, open: @escaping (ReadingTarget) -> Void) -> some View {
        modifier(ReaderToolbars(session: session, width: width, opening: opening, open: open))
    }
}

private struct ReaderToolbars: ViewModifier {
    let session: ReaderSession
    /// The screen's width. Toolbar items size to their content, and a
    /// slider has none, so the scrubber is given its width.
    let width: CGFloat
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
                // One button either side, so the title sits in the visual
                // middle, not just the measured one. Appearance goes with
                // the scrubber at the bottom, as in Books.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Contents", systemImage: "list.bullet") {
                        session.show(.contents)
                    }
                    .disabled(session.controller.state != .ready)
                }
                // The chapters either side, beside the scrubber, as in
                // Mihon and Webtoon: going on never needs the contents.
                if session.item.series != nil {
                    ToolbarItem(placement: .bottomBar) {
                        SeriesStepButton(lookup: session.previous, direction: .previous, isChapter: session.item.sourceChapter != nil, opening: opening, open: open)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    ReaderScrubber(controller: session.controller)
                        .frame(width: min(max(width - (session.item.series == nil ? 136 : 232), 120), 500))
                }
                if session.item.series != nil {
                    ToolbarItem(placement: .bottomBar) {
                        SeriesStepButton(lookup: session.next, direction: .next, isChapter: session.item.sourceChapter != nil, opening: opening, open: open)
                    }
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Appearance", systemImage: session.showsTextSettings ? "textformat.size" : "slider.horizontal.3") {
                        session.show(.appearance)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Only the glass controls float over the page; the bars
            // themselves draw nothing, so no band of another color shows.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar, .bottomBar)

            // Contents and the scrubber need an open publication; while
            // there isn't one, only Close is of any use.
            .toolbarVisibility(session.isShowingControls ? .visible : .hidden, for: .navigationBar)
            .toolbarVisibility(session.isShowingControls && session.controller.state == .ready ? .visible : .hidden, for: .bottomBar)
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
                case .appearance:
                    AppearancePanel(
                        showsTextSettings: session.showsTextSettings,
                        showsComicSettings: session.item.kind == .comic,
                        // Only pictures have a direction to get wrong;
                        // text follows its language.
                        directionKey: session.showsTextSettings ? nil : session.item.settingsKey
                    )
                }
            }
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
            PlaceLabel(showsPages: showsPages, position: Int(scrubbing ?? position), count: count, progress: progress(count: count))
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
    let showsPages: Bool
    let position: Int
    let count: Int
    let progress: Double?

    var body: some View {
        Group {
            if showsPages, count > 0 {
                Text("\(position) of \(count)")
            } else if let progress {
                Text(progress, format: .percent.precision(.fractionLength(0)))
            }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .fixedSize()
    }
}

