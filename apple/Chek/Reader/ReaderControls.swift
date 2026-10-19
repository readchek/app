import ChekReader
import SwiftUI

extension View {
    /// The reader's toolbars, shown and hidden together.
    func readerToolbars(session: ReaderSession, width: CGFloat) -> some View {
        modifier(ReaderToolbars(session: session, width: width))
    }
}

private struct ReaderToolbars: ViewModifier {
    let session: ReaderSession
    /// The screen's width. Toolbar items size to their content, and a
    /// slider has none, so the scrubber is given its width.
    let width: CGFloat
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
                    ReaderTitle(title: session.item.title, controller: session.controller)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Contents", systemImage: "list.bullet") {
                        session.show(.contents)
                    }
                    if session.showsAppearance {
                        Button("Appearance", systemImage: "textformat.size") {
                            session.show(.appearance)
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    ReaderScrubber(controller: session.controller)
                        .frame(width: min(max(width - 72, 200), 560))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(session.isShowingControls ? .visible : .hidden, for: .navigationBar, .bottomBar)
            .animation(.smooth(duration: 0.25), value: session.isShowingControls)
            .sheet(item: Bindable(session).panel) { panel in
                switch panel {
                case .contents:
                    ContentsPanel(session: session)
                case .appearance:
                    AppearancePanel()
                }
            }
    }
}

/// The publication's title, with the chapter you're in under it.
private struct ReaderTitle: View {
    let title: String
    let controller: ReaderController

    var body: some View {
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
        let position = Double(controller.location?.locations.position ?? 1)
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
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}
